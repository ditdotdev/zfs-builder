#!/bin/bash
#
# Copyright The Datadatdat Project Contributors.
#

#
# apt-get can hang on poor network connections. This will enforce a reasonble
# timeout and retry the download if it takes too long.
#
function safe_apt_get() {
    local retry=3 count=0

    while true; do
        if timeout 60 apt-get install --download-only -y --fix-missing $*; then
            break
        fi
        if (( count++ == retry )); then
            printf 'Download $* failed\n' >&2
            exit 1
        fi
    done

    apt-get install -y $*
}

#
# Get ubuntu-specific modules. With Ubuntu, we can get the pre-built modules and
# headers for a given kernel release, so that we don't need to actually build from source.
#
function get_kernel() {
    apt-get update
    # Install build tools needed for kernel preparation
    safe_apt_get build-essential bc bison flex libelf-dev libssl-dev gcc-12
    safe_apt_get linux-modules-$KERNEL_RELEASE
    safe_apt_get linux-headers-$KERNEL_RELEASE
    
    # Extract major.minor version (e.g., 6.8.0 -> 6.8) for source package lookup
    KERNEL_MAJOR_MINOR=$(echo $KERNEL_VERSION | cut -d. -f1,2)
    KERNEL_MAJOR=$(echo $KERNEL_VERSION | cut -d. -f1)
    
    # For standard Ubuntu kernels (including HWE kernels), the headers package
    # contains everything needed to build modules. Only use linux-source if
    # headers are insufficient (which is rare).
    # The headers are always the correct version matching the running kernel.
    echo "Using kernel headers from /lib/modules/$KERNEL_RELEASE/build"
    KERNEL_SRC=/lib/modules/$KERNEL_RELEASE/build
    KERNEL_OBJ=/lib/modules/$KERNEL_RELEASE/build
    
    # Verify the headers have the necessary config
    if [ ! -f "$KERNEL_SRC/.config" ]; then
        echo "ERROR: .config not found in headers at $KERNEL_SRC"
        exit 1
    fi
    
    # Check if CONFIG_MODULES is enabled
    if ! grep -q "^CONFIG_MODULES=y" "$KERNEL_SRC/.config"; then
        echo "ERROR: CONFIG_MODULES not enabled in headers .config"
        exit 1
    fi
    
    echo "Headers verified with CONFIG_MODULES=y at $KERNEL_SRC"
    
    # Ensure the headers are fully prepared for module building
    # This fixes any .config issues and ensures scripts/binaries are built
    cd $KERNEL_SRC
    make oldconfig </dev/null 2>/dev/null || true
    make scripts
    make modules_prepare
    
    # Legacy code path: Try linux-source (kept for reference but shouldn't be needed)
    if false && apt-cache show linux-source-$KERNEL_MAJOR_MINOR >/dev/null 2>&1; then
        echo "Found linux-source-$KERNEL_MAJOR_MINOR"
        safe_apt_get linux-source-$KERNEL_MAJOR_MINOR
        # Find the actual tar file that was created (may have full version in name)
        TARBALL=$(ls /usr/src/linux-source-*.tar.bz2 | head -n1)
        if [ -n "$TARBALL" ]; then
            cd /usr/src && tar -xjf $(basename $TARBALL)
            KERNEL_SRC=$(echo $TARBALL | sed 's/.tar.bz2$//')
            # Prepare the kernel source with config from headers
            echo "Preparing kernel source with config from headers..."
            cp /lib/modules/$KERNEL_RELEASE/build/.config $KERNEL_SRC/
            cd $KERNEL_SRC
            make scripts
            make modules_prepare
            # Copy Module.symvers if it exists in headers
            if [ -f /lib/modules/$KERNEL_RELEASE/build/Module.symvers ]; then
                cp /lib/modules/$KERNEL_RELEASE/build/Module.symvers $KERNEL_SRC/
            fi
            # Use prepared source for both src and obj
            KERNEL_OBJ=$KERNEL_SRC
        else
            echo "ERROR: No linux-source tarball found in /usr/src"
            exit 1
        fi
    elif apt-cache show linux-source-$KERNEL_VERSION >/dev/null 2>&1; then
        echo "Found linux-source-$KERNEL_VERSION"
        safe_apt_get linux-source-$KERNEL_VERSION
        # Find the actual tar file that was created
        TARBALL=$(ls /usr/src/linux-source-*.tar.bz2 | head -n1)
        if [ -n "$TARBALL" ]; then
            cd /usr/src && tar -xjf $(basename $TARBALL)
            KERNEL_SRC=$(echo $TARBALL | sed 's/.tar.bz2$//')
            # Prepare the kernel source with config from headers
            echo "Preparing kernel source with config from headers..."
            cp /lib/modules/$KERNEL_RELEASE/build/.config $KERNEL_SRC/
            cd $KERNEL_SRC
            make scripts
            make modules_prepare
            # Copy Module.symvers if it exists in headers
            if [ -f /lib/modules/$KERNEL_RELEASE/build/Module.symvers ]; then
                cp /lib/modules/$KERNEL_RELEASE/build/Module.symvers $KERNEL_SRC/
            fi
            # Use prepared source for both src and obj
            KERNEL_OBJ=$KERNEL_SRC
        else
            echo "ERROR: No linux-source tarball found in /usr/src"
            exit 1
        fi
    else
        echo "linux-source not available, using headers only"
        KERNEL_SRC=/lib/modules/$KERNEL_RELEASE/build
        KERNEL_OBJ=/lib/modules/$KERNEL_RELEASE/build
    fi
}

function build() {
    get_zfs_source
    if [ "$ZFS_CONFIG" != "user" ]; then
        get_kernel
    fi
    build_zfs
}
