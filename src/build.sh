#!/bin/bash
#
# Copyright The Datadatdat Project Contributors.
#

set -xe

. $(dirname $0)/common.sh

# Configurable system paths for testing. Default to real paths.
: "${ZFS_PROC_FILESYSTEMS:=/proc/filesystems}"
: "${ZFS_DEV_ZFS:=/dev/zfs}"

# Check if ZFS is already available in the system
function check_zfs_availability() {
    echo "Checking if ZFS is already available..."

    # Check if ZFS filesystem is supported in kernel
    if grep -q "^nodev.*zfs" "$ZFS_PROC_FILESYSTEMS" 2>/dev/null; then
        echo "✓ ZFS kernel support detected"
        ZFS_KERNEL_AVAILABLE=1
    else
        echo "✗ ZFS kernel support not found"
        ZFS_KERNEL_AVAILABLE=0
    fi
    
    # Check if ZFS device node exists
    if [ -c "$ZFS_DEV_ZFS" ]; then
        echo "✓ ZFS device node (/dev/zfs) available"
        ZFS_DEVICE_AVAILABLE=1
    else
        echo "✗ ZFS device node (/dev/zfs) not found"
        ZFS_DEVICE_AVAILABLE=0
    fi
    
    # Check if ZFS userspace tools are available
    if command -v zpool >/dev/null 2>&1; then
        echo "✓ ZFS userspace tools (zpool) available"
        ZFS_USERSPACE_AVAILABLE=1
    else
        echo "✗ ZFS userspace tools not found"
        ZFS_USERSPACE_AVAILABLE=0
    fi
    
    # Kernel support alone is sufficient to skip the build. Inside a container,
    # /dev/zfs and zpool won't exist even when ZFS is built into the host kernel.
    if [ "$ZFS_KERNEL_AVAILABLE" = "1" ]; then
        echo "ZFS kernel support detected. No kernel build needed."
        return 0
    else
        echo "ZFS kernel support not detected. Kernel build required."
        return 1
    fi
}

function get_kernel_vars() {
    [ -z "$KERNEL_RELEASE" ] && KERNEL_RELEASE=$(uname -r)
    [ -z "$KERNEL_UNAME" ] && KERNEL_UNAME=$(uname -a)
    KERNEL_VERSION=${KERNEL_RELEASE%%-*}
    KERNEL_VARIANT=${KERNEL_RELEASE#*-}
}

function get_kernel_type() {
    case $KERNEL_VARIANT in
    linuxkit)
        echo linuxkit
        ;;
    microsoft-standard*)
        echo wsl
        ;;
    *)
        case $KERNEL_UNAME in
        *Ubuntu*)
            echo ubuntu
            ;;
        *.el[0-9].*)
            echo centos
            ;;
        *.el8_[0-9].*)
	    echo centos8x
            ;;
        *)
            echo vanilla
            ;;
        esac
    esac
}

if [ "$ZFS_CONFIG" != "user" ]; then
    get_kernel_vars
    kernel_type=$(get_kernel_type)

    # In CI builds, skip the ZFS availability check — we always want to build
    if [ "${CI_BUILD:-0}" != "1" ]; then
        # Check if ZFS is already available before building
        echo "Starting ZFS availability check..."
        if check_zfs_availability; then
            echo "ZFS is already fully available - skipping kernel build"
            echo "Current kernel: $(uname -r)"
            echo "ZFS support: COMPLETE"
            echo "No build required!"
            exit 0
        fi

        echo "ZFS not fully available - proceeding with kernel build for type: $kernel_type"
    else
        echo "CI_BUILD=1: skipping ZFS availability check, proceeding with build for type: $kernel_type"
    fi
else
    kernel_type=vanilla
fi

. $(dirname $0)/$kernel_type.sh
build

# Package modules if /output directory is mounted
if [ -d /output ]; then
    echo "Packaging ZFS modules for export..."
    if [ -d /build/lib/modules ]; then
        ARCH=$(uname -m)
        case $ARCH in
            x86_64) ARCH_SUFFIX="amd64" ;;
            aarch64) ARCH_SUFFIX="arm64" ;;
            *) ARCH_SUFFIX=$ARCH ;;
        esac
        
        ZFS_VER=$(grep -oP 'VERSION="\K[^"]+' /src/zfs/META 2>/dev/null || echo "unknown")
        OUTPUT_FILE="/output/zfs-${ZFS_VER}-${KERNEL_RELEASE}-${ARCH_SUFFIX}.tar.gz"
        
        echo "Creating $OUTPUT_FILE..."
        tar -czf "$OUTPUT_FILE" -C /build/lib/modules .
        echo "✓ Module package created: $(ls -lh $OUTPUT_FILE)"
    else
        echo "⚠️  No modules found in /build/lib/modules - skipping packaging"
    fi
fi
