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
    safe_apt_get build-essential bc bison flex libelf-dev libssl-dev
    safe_apt_get linux-modules-$KERNEL_RELEASE
    safe_apt_get linux-headers-$KERNEL_RELEASE
    
    # Extract major.minor version (e.g., 6.8.0 -> 6.8) for source package lookup
    KERNEL_MAJOR_MINOR=$(echo $KERNEL_VERSION | cut -d. -f1,2)
    KERNEL_MAJOR=$(echo $KERNEL_VERSION | cut -d. -f1)
    
    # For HWE kernels (like 6.8.0-64 backported to 22.04), the headers contain
    # everything needed. Skip linux-source which would have version mismatch.
    if [[ $KERNEL_RELEASE =~ ^6\.8\.0-[0-9]+-generic$ ]]; then
        echo "Detected HWE kernel $KERNEL_RELEASE, using headers only (no linux-source)"
        KERNEL_SRC=/lib/modules/$KERNEL_RELEASE/build
        KERNEL_OBJ=/lib/modules/$KERNEL_RELEASE/build
        
        # Prepare the headers directory for module building
        echo "Preparing headers with make modules_prepare..."
        cd $KERNEL_SRC
        make modules_prepare
    # Try with major.minor first (newer format), fall back to full version
    elif apt-cache show linux-source-$KERNEL_MAJOR_MINOR >/dev/null 2>&1; then
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
