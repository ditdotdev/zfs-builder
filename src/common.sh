# shellcheck shell=bash
#
# Copyright The Datadatdat Project Contributors.
#
# Sourced by build.sh and other entry-point scripts. No shebang because this
# file is never executed directly; the directive above tells the linter which
# dialect to use.
#

# Generate a random string
function generate_random_string() {
    local length=$1
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w "$length" | head -n 1
}

# Checkout ZFS source
function get_zfs_source() {
    if [ ! -d /src/zfs ]; then
        git clone https://github.com/zfsonlinux/zfs.git /src/zfs
        cd /src/zfs || exit 1
        [ -z "$ZFS_VERSION" ] && ZFS_VERSION=$(git describe --tags "$(git rev-list --tags --max-count=1)")
        git checkout "$ZFS_VERSION"
    fi
}

# Build ZFS
function build_zfs() {
    cd /src/zfs || exit 1
    sh ./autogen.sh
    ./configure \
        --prefix=/ \
        --libdir=/lib \
        --with-linux="$KERNEL_SRC" \
        --with-linux-obj="$KERNEL_OBJ" \
        --with-config="${ZFS_CONFIG:-all}"
    make -j8
    make install DESTDIR=/build
}
