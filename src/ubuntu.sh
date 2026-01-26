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
    safe_apt_get linux-modules-$KERNEL_RELEASE
    safe_apt_get linux-headers-$KERNEL_RELEASE
    
    # Extract major.minor version (e.g., 6.8.0 -> 6.8) for source package lookup
    KERNEL_MAJOR_MINOR=$(echo $KERNEL_VERSION | cut -d. -f1,2)
    KERNEL_MAJOR=$(echo $KERNEL_VERSION | cut -d. -f1)
    
    # Kernel 6.8+ requires Ubuntu 24.04 (noble) repos
    if [[ $KERNEL_MAJOR -ge 6 ]] && [[ $(echo $KERNEL_VERSION | cut -d. -f2) -ge 8 ]]; then
        echo "Kernel $KERNEL_VERSION requires noble (24.04) repos, adding them..."
        echo "deb http://archive.ubuntu.com/ubuntu noble main restricted universe" >> /etc/apt/sources.list
        echo "deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe" >> /etc/apt/sources.list
        apt-get update
    fi
    
    # Try with major.minor first (newer format), fall back to full version
    if apt-cache show linux-source-$KERNEL_MAJOR_MINOR >/dev/null 2>&1; then
        echo "Found linux-source-$KERNEL_MAJOR_MINOR"
        safe_apt_get linux-source-$KERNEL_MAJOR_MINOR
        cd /usr/src && tar -xjf linux-source-$KERNEL_MAJOR_MINOR.tar.bz2
        KERNEL_SRC=/usr/src/linux-source-$KERNEL_MAJOR_MINOR
    elif apt-cache show linux-source-$KERNEL_VERSION >/dev/null 2>&1; then
        echo "Found linux-source-$KERNEL_VERSION"
        safe_apt_get linux-source-$KERNEL_VERSION
        cd /usr/src && tar -xjf linux-source-$KERNEL_VERSION.tar.bz2
        KERNEL_SRC=/usr/src/linux-source-$KERNEL_VERSION
    else
        echo "linux-source not available, using headers only"
        KERNEL_SRC=/lib/modules/$KERNEL_RELEASE/build
    fi
    
    KERNEL_OBJ=/lib/modules/$KERNEL_RELEASE/build
}

function build() {
    get_zfs_source
    if [ "$ZFS_CONFIG" != "user" ]; then
        get_kernel
    fi
    build_zfs
}
