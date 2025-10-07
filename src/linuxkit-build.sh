#!/bin/bash
#
# Copyright The Titan Project Contributors.
#

set -xe

. $(dirname $0)/common.sh

# Set up kernel header symlinks for LinuxKit
# LinuxKit extracts kernel headers to /usr/src/linux-headers-$KERNEL_RELEASE/
# but ZFS expects them at /lib/modules/$KERNEL_RELEASE/build
mkdir -p /lib/modules/$KERNEL_RELEASE
ln -sf /usr/src/linux-headers-$KERNEL_RELEASE /lib/modules/$KERNEL_RELEASE/build

# Also create a symlink at /src/linux for the source directory
mkdir -p /src
ln -sf /usr/src/linux-headers-$KERNEL_RELEASE /src/linux

# Check if ZFS is already available in kernel (similar to WSL approach)
function check_zfs_availability() {
    echo "Checking if ZFS kernel support is already available..."
    
    # Check if ZFS filesystem is supported in kernel
    if grep -q "^nodev.*zfs" /proc/filesystems 2>/dev/null; then
        echo "✓ ZFS kernel support detected in /proc/filesystems"
        echo "🎉 ZFS is built into the LinuxKit kernel! No kernel build needed."
        echo "Current kernel: $(uname -r)"
        echo "ZFS filesystem support: AVAILABLE"
        return 0
    else
        echo "✗ ZFS kernel support not found in /proc/filesystems"
        echo "⚠️  ZFS kernel compilation required but LinuxKit doesn't support it."
        return 1
    fi
}

# Check if ZFS userspace tools are available in package repositories
function check_zfs_packages() {
    echo "Checking for ZFS userspace tools in package repositories..."
    
    # Check for Alpine packages (LinuxKit uses Alpine)
    if command -v apk >/dev/null 2>&1; then
        echo "Alpine package manager detected, checking for zfs packages..."
        if apk search zfs | grep -q "zfs"; then
            echo "✓ ZFS packages found in Alpine repositories"
            return 0
        else
            echo "✗ No ZFS packages found in Alpine repositories"
            return 1
        fi
    fi
    
    # Check for Ubuntu/Debian packages (build container uses Ubuntu)
    if command -v apt >/dev/null 2>&1; then
        echo "Ubuntu/Debian package manager detected, checking for zfs packages..."
        apt update >/dev/null 2>&1
        if apt search zfsutils-linux 2>/dev/null | grep -q "zfsutils-linux"; then
            echo "✓ ZFS packages found in Ubuntu repositories"
            return 0
        else
            echo "✗ No ZFS packages found in Ubuntu repositories"
            return 1
        fi
    fi
    
    echo "✗ No supported package manager found"
    return 1
}

# Install ZFS userspace tools from packages
function install_zfs_packages() {
    echo "Installing ZFS userspace tools from package repositories..."
    
    # Alpine installation
    if command -v apk >/dev/null 2>&1; then
        echo "Installing ZFS packages via apk..."
        apk add --no-cache zfs || return 1
        
        # Create build directory structure
        mkdir -p /build/sbin /build/bin /build/lib /build/etc
        
        # Copy ZFS binaries and libraries
        cp /sbin/zfs /build/sbin/ 2>/dev/null || true
        cp /sbin/zpool /build/sbin/ 2>/dev/null || true
        cp /usr/sbin/zfs* /build/sbin/ 2>/dev/null || true
        cp /usr/sbin/zpool* /build/sbin/ 2>/dev/null || true
        cp /bin/zfs* /build/bin/ 2>/dev/null || true
        cp /usr/bin/zfs* /build/bin/ 2>/dev/null || true
        
        # Copy libraries
        cp /lib/libzfs* /build/lib/ 2>/dev/null || true
        cp /lib/libnvpair* /build/lib/ 2>/dev/null || true
        cp /lib/libuutil* /build/lib/ 2>/dev/null || true
        cp /lib/libzpool* /build/lib/ 2>/dev/null || true
        cp /usr/lib/libzfs* /build/lib/ 2>/dev/null || true
        cp /usr/lib/libnvpair* /build/lib/ 2>/dev/null || true
        cp /usr/lib/libuutil* /build/lib/ 2>/dev/null || true
        cp /usr/lib/libzpool* /build/lib/ 2>/dev/null || true
        
        # Copy configuration files
        cp -r /etc/zfs* /build/etc/ 2>/dev/null || true
        
        echo "✓ ZFS userspace tools installed via Alpine packages"
        return 0
    fi
    
    # Ubuntu/Debian installation
    if command -v apt >/dev/null 2>&1; then
        echo "Installing ZFS packages via apt..."
        apt update
        apt install -y zfsutils-linux || return 1
        
        # Copy installed files to build directory
        mkdir -p /build/sbin /build/lib /build/etc
        cp -r /usr/sbin/zfs* /build/sbin/ 2>/dev/null || true
        cp -r /usr/sbin/zpool* /build/sbin/ 2>/dev/null || true
        cp -r /sbin/zfs* /build/sbin/ 2>/dev/null || true
        cp -r /sbin/zpool* /build/sbin/ 2>/dev/null || true
        cp -r /lib/x86_64-linux-gnu/libzfs* /build/lib/ 2>/dev/null || true
        cp -r /lib/x86_64-linux-gnu/libnvpair* /build/lib/ 2>/dev/null || true
        cp -r /lib/x86_64-linux-gnu/libuutil* /build/lib/ 2>/dev/null || true
        cp -r /lib/x86_64-linux-gnu/libzpool* /build/lib/ 2>/dev/null || true
        cp -r /etc/zfs* /build/etc/ 2>/dev/null || true
        
        echo "✓ ZFS userspace tools installed via Ubuntu packages"
        return 0
    fi
    
    echo "✗ No supported package manager found for installation"
    return 1
}

# Workaround for musl libc missing SEEK_DATA/SEEK_HOLE constants
# Alpine Linux (musl) doesn't define these in unistd.h
export CPPFLAGS="${CPPFLAGS} -DSEEK_DATA=3 -DSEEK_HOLE=4"

# Check if ZFS is already built into the kernel
if check_zfs_availability; then
    echo "✓ ZFS kernel support already available - checking for userspace tools"
    
    # Try to install from packages first
    if check_zfs_packages && install_zfs_packages; then
        # Create marker file to inform build script we're doing userspace-only
        mkdir -p /build && touch /build/.zfs-userspace-only
        echo "✓ ZFS userspace tools installed from packages"
        exit 0
    else
        echo "⚠️  Package installation failed, falling back to source compilation"
        # Fall through to source compilation below
    fi
else
    echo "✗ ZFS kernel support not available - LinuxKit requires built-in ZFS"
    echo ""
    echo "🔧 LinuxKit ZFS Built-in Requirements:"
    echo "   LinuxKit kernels don't support loadable modules (CONFIG_MODULES=n)"
    echo "   ZFS must be compiled into the kernel at build time"
    echo ""
    echo "💡 Solutions:"
    echo "   1. Use a LinuxKit image with ZFS pre-built:"
    echo "      - Custom LinuxKit .yml with ZFS kernel package"
    echo "      - Pre-built LinuxKit image with ZFS support"
    echo "   2. Build LinuxKit kernel from source with ZFS built-in:"
    echo "      - Clone LinuxKit kernel source"
    echo "      - Configure with --enable-linux-builtin=yes"
    echo "      - Use ./copy-builtin to embed ZFS"
    echo "      - Add CONFIG_ZFS=y to kernel config"
    echo "      - Build complete kernel image"
    echo ""
    echo "🚧 Fallback: Building userspace tools only"
    echo "   (Will not provide ZFS filesystem functionality)"
fi

# Get ZFS source for compilation
get_zfs_source

# ZFS source compilation as fallback
cd /src/zfs
sh ./autogen.sh

# Determine build configuration based on kernel support
if check_zfs_availability; then
    echo "Building userspace tools only (kernel support already available)"
    build_config="user"
    mkdir -p /build && touch /build/.zfs-userspace-only
else
    echo "Attempting to configure ZFS for kernel modules..."
    build_config="${ZFS_CONFIG:-kernel}"
fi

if [[ $build_config == "user" ]] || ./configure \
    --prefix=/ \
    --libdir=/lib \
    --with-linux=$KERNEL_SRC \
    --with-linux-obj=$KERNEL_OBJ \
    --with-config=$build_config; then
    
    if [[ $build_config == "user" ]]; then
        echo "✓ Building ZFS userspace tools only"
        ./configure \
            --prefix=/ \
            --libdir=/lib \
            --with-config=user
    else
        echo "✓ Kernel modules supported, building ZFS as loadable modules"
    fi
    
    make -j8
    make install DESTDIR=/build
    echo "✓ ZFS tools built successfully from source"
else
    echo "✗ Kernel modules not supported (CONFIG_MODULES=n)"
    echo ""
    echo "🔧 LinuxKit ZFS Built-in Requirements:"
    echo "   LinuxKit kernels don't support loadable modules (CONFIG_MODULES=n)"
    echo "   ZFS must be compiled into the kernel at build time"
    echo ""
    echo "💡 Solutions:"
    echo "   1. Use a LinuxKit image with ZFS pre-built:"
    echo "      - Custom LinuxKit .yml with ZFS kernel package"
    echo "      - Pre-built LinuxKit image with ZFS support"
    echo "   2. Build LinuxKit kernel from source with ZFS built-in:"
    echo "      - Clone LinuxKit kernel source"
    echo "      - Configure with --enable-linux-builtin=yes"
    echo "      - Use ./copy-builtin to embed ZFS"
    echo "      - Add CONFIG_ZFS=y to kernel config"
    echo "      - Build complete kernel image"
    echo ""
    echo "🚧 Fallback: Building userspace tools only"
    echo "   (Will not provide ZFS filesystem functionality)"
    
    # Set ZFS_CONFIG to user for proper archive creation
    export ZFS_CONFIG=user
    
    # Create marker file to inform build script we're doing userspace-only
    mkdir -p /build && touch /build/.zfs-userspace-only
    
    ./configure \
        --prefix=/ \
        --libdir=/lib \
        --with-config=user
    make -j8
    make install DESTDIR=/build
    
    echo ""
    echo "⚠️  LinuxKit ZFS Status:"
    echo "   - Userspace tools: INSTALLED (zpool, zfs commands)"
    echo "   - Kernel support: NOT AVAILABLE"
    echo "   - ZFS filesystem: NOT FUNCTIONAL"
    echo "   - Recommendation: Use LinuxKit with pre-built ZFS kernel"
    echo ""
fi