#!/bin/bash
#
# Copyright The Datadatdat Project Contributors.
#

#
# Map a kernel release string to the Ubuntu codename whose archive ships it.
# Returns empty for kernels not tied to an Ubuntu release.
#
# Generic kernels live only in their original release. Cloud-variant kernels
# (azure, aws, gcp) are also backported to the latest LTS as HWE updates, so
# noble's noble-updates pocket carries the full series — the practical place
# to fetch them from since interim releases (oracular, plucky, questing) reach
# EOL quickly and move to old-releases.ubuntu.com.
#
function ubuntu_codename_for_kernel() {
    case $1 in
        5.4.0-*-generic)   echo focal ;;
        5.15.0-*-generic)  echo jammy ;;
        6.8.0-*-generic)   echo noble ;;

        5.4.0-*-azure|5.4.0-*-aws|5.4.0-*-gcp)        echo focal ;;
        5.15.0-*-azure|5.15.0-*-aws|5.15.0-*-gcp)     echo jammy ;;
        *-azure|*-aws|*-gcp)                          echo noble ;;
    esac
}

#
# When the container's Ubuntu release differs from the target kernel's release,
# add an apt source for the target release so we can pull its kernel packages.
# Pin the new source narrowly to linux-* packages so unrelated packages (libc6
# etc.) keep coming from the container's own release.
#
function add_kernel_apt_source() {
    local codename
    codename=$(ubuntu_codename_for_kernel "$KERNEL_RELEASE")
    [[ -z $codename ]] && return 0

    local current_codename
    # shellcheck disable=SC1091  # /etc/os-release is a runtime file, not a script to follow at lint time
    current_codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
    [[ $codename = "$current_codename" ]] && return 0

    local arch mirror security_mirror
    arch=$(dpkg --print-architecture)
    case $arch in
        amd64|i386)
            mirror=http://archive.ubuntu.com/ubuntu
            security_mirror=http://security.ubuntu.com/ubuntu
            ;;
        *)
            mirror=http://ports.ubuntu.com/ubuntu-ports
            security_mirror=http://ports.ubuntu.com/ubuntu-ports
            ;;
    esac

    echo "Adding $codename apt sources for kernel $KERNEL_RELEASE (container is $current_codename)"
    cat > /etc/apt/sources.list.d/"$codename"-kernel.sources <<EOF
Types: deb
URIs: $mirror
Suites: $codename $codename-updates
Components: main universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: $security_mirror
Suites: $codename-security
Components: main universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

    cat > /etc/apt/preferences.d/"$codename"-kernel <<EOF
Package: linux-modules-* linux-modules-extra-* linux-headers-* linux-image-*
Pin: release n=$codename
Pin-Priority: 990

Package: *
Pin: release n=$codename
Pin-Priority: 100
EOF
}

#
# apt-get can hang on poor network connections. This will enforce a reasonble
# timeout and retry the download if it takes too long.
#
function safe_apt_get() {
    local retry=3 count=0

    while true; do
        if timeout 60 apt-get install --download-only -y --fix-missing "$@"; then
            break
        fi
        if (( count++ == retry )); then
            printf 'Download %s failed\n' "$*" >&2
            exit 1
        fi
    done

    apt-get install -y "$@"
}

#
# Get ubuntu-specific modules. With Ubuntu, we can get the pre-built modules and
# headers for a given kernel release, so that we don't need to actually build from source.
#
function get_kernel() {
    add_kernel_apt_source
    apt-get update
    # Install build tools needed for kernel preparation
    safe_apt_get build-essential bc bison flex libelf-dev libssl-dev
    safe_apt_get linux-modules-"$KERNEL_RELEASE"
    safe_apt_get linux-headers-"$KERNEL_RELEASE"

    # Match the gcc major version the kernel was built with — the container's
    # default cc may be too new (e.g. 26.04 ships gcc-15, but a Noble 6.8 kernel
    # was built with gcc-13). Mismatched gcc fails ZFS's configure-time module
    # compile test with a misleading "CONFIG_MODULES not defined" error.
    local kernel_gcc_major
    kernel_gcc_major=$(grep -oP 'CONFIG_CC_VERSION_TEXT.*?gcc-\K[0-9]+' \
        /lib/modules/"$KERNEL_RELEASE"/build/.config | head -1)
    if [[ -n $kernel_gcc_major ]] && ! command -v gcc-"$kernel_gcc_major" >/dev/null; then
        echo "Kernel was built with gcc-$kernel_gcc_major; installing it"
        safe_apt_get gcc-"$kernel_gcc_major"
    fi
    if [[ -n $kernel_gcc_major ]]; then
        echo "Selecting gcc-$kernel_gcc_major as default cc/gcc"
        update-alternatives --install /usr/bin/cc cc "/usr/bin/gcc-$kernel_gcc_major" 100
        update-alternatives --install /usr/bin/gcc gcc "/usr/bin/gcc-$kernel_gcc_major" 100
        export CC="gcc-$kernel_gcc_major"
    fi

    # The Ubuntu kernel headers package contains everything needed to build
    # modules — symbol versions, .config, scripts/, etc. — so we always use
    # the headers tree directly. KERNEL_SRC and KERNEL_OBJ are consumed by
    # build_zfs() in common.sh.
    # shellcheck disable=SC2034  # exported via sourcing
    KERNEL_SRC=/lib/modules/$KERNEL_RELEASE/build
    # shellcheck disable=SC2034  # exported via sourcing
    KERNEL_OBJ=/lib/modules/$KERNEL_RELEASE/build
    echo "Using kernel headers from $KERNEL_SRC"

    if [ ! -f "$KERNEL_SRC/.config" ]; then
        echo "ERROR: .config not found in headers at $KERNEL_SRC"
        exit 1
    fi
    if ! grep -q "^CONFIG_MODULES=y" "$KERNEL_SRC/.config"; then
        echo "ERROR: CONFIG_MODULES not enabled in headers .config"
        exit 1
    fi
    echo "Headers verified with CONFIG_MODULES=y at $KERNEL_SRC"
}

function build() {
    get_zfs_source
    if [ "$ZFS_CONFIG" != "user" ]; then
        get_kernel
    fi
    build_zfs
}
