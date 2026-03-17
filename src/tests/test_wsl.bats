#!/usr/bin/env bats
#
# Tests for wsl.sh CI-compatibility changes.
#
# These tests verify that wsl.sh functions behave correctly when
# configured for CI builds (WSL2_KERNEL_TAG, CI_BUILD=1, etc.)
#

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    TEST_TMPDIR="$(mktemp -d)"

    # Source wsl.sh to get function definitions
    # Set required vars that wsl.sh expects
    export KERNEL_RELEASE="6.6.75.2-microsoft-standard-WSL2"
    export KERNEL_VERSION="6.6.75.2"

    source "$SCRIPT_DIR/wsl.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# get_kernel_src() — WSL2_KERNEL_TAG env var support
# =============================================================================

@test "get_kernel_src uses WSL2_KERNEL_TAG when set (skips GitHub API)" {
    export WSL2_KERNEL_TAG="linux-msft-wsl-6.6.75.2"
    export KERNELDIR="$TEST_TMPDIR/kernel"

    # Mock curl to fail — proves WSL2_KERNEL_TAG bypasses the API
    curl() { echo "CURL_SHOULD_NOT_BE_CALLED" >&2; return 1; }
    export -f curl

    # Mock git clone to just create the directory
    git() {
        if [ "$1" = "clone" ]; then
            mkdir -p "$KERNELDIR"
            # Verify the tag passed to git clone matches WSL2_KERNEL_TAG
            echo "CLONE_ARGS: $*" > "$TEST_TMPDIR/git_args"
            return 0
        fi
        command git "$@"
    }
    export -f git

    run get_kernel_src

    [ "$status" -eq 0 ]
    # Verify WSL2_KERNEL_TAG was used (not derived from uname/API)
    [ -f "$TEST_TMPDIR/git_args" ]
    grep -q "linux-msft-wsl-6.6.75.2" "$TEST_TMPDIR/git_args"
}

@test "get_kernel_src derives tag from KERNEL_RELEASE when WSL2_KERNEL_TAG not set" {
    unset WSL2_KERNEL_TAG
    export KERNELDIR="$TEST_TMPDIR/kernel"

    # Mock curl to return empty (no matching release)
    curl() { echo "[]"; }
    export -f curl

    # Mock jq
    jq() { echo ""; }
    export -f jq

    # Mock git clone
    git() {
        if [ "$1" = "clone" ]; then
            mkdir -p "$KERNELDIR"
            echo "CLONE_ARGS: $*" > "$TEST_TMPDIR/git_args"
            return 0
        fi
        command git "$@"
    }
    export -f git

    run get_kernel_src

    # Should still attempt to clone (using fallback tag from latest release)
    [ "$status" -eq 0 ]
}

# =============================================================================
# build() — CI_BUILD=1 bypass
# =============================================================================

@test "build skips check_zfs_availability when CI_BUILD=1" {
    export CI_BUILD=1

    # Track which functions are called
    local call_log="$TEST_TMPDIR/call_log"
    echo "" > "$call_log"

    # Override functions to just log calls
    check_zfs_availability() { echo "check_zfs_availability" >> "$call_log"; return 0; }
    install_dependencies() { echo "install_dependencies" >> "$call_log"; }
    get_kernel_src() { echo "get_kernel_src" >> "$call_log"; }
    prepare_kernel() { echo "prepare_kernel" >> "$call_log"; }
    get_zfs_builtin() { echo "get_zfs_builtin" >> "$call_log"; }
    configure_zfs_builtin() { echo "configure_zfs_builtin" >> "$call_log"; }
    build_kernel() { echo "build_kernel" >> "$call_log"; }

    run build

    [ "$status" -eq 0 ]
    # check_zfs_availability should NOT have been called
    ! grep -q "check_zfs_availability" "$call_log"
    # But build steps SHOULD have been called
    grep -q "install_dependencies" "$call_log"
    grep -q "get_kernel_src" "$call_log"
    grep -q "prepare_kernel" "$call_log"
}

@test "build calls check_zfs_availability when CI_BUILD is not set" {
    unset CI_BUILD

    local call_log="$TEST_TMPDIR/call_log"
    echo "" > "$call_log"

    # check_zfs_availability returns 0 (ZFS available) to short-circuit
    check_zfs_availability() { echo "check_zfs_availability" >> "$call_log"; return 0; }
    install_dependencies() { echo "install_dependencies" >> "$call_log"; }

    run build

    [ "$status" -eq 0 ]
    # check_zfs_availability SHOULD have been called
    grep -q "check_zfs_availability" "$call_log"
    # Build steps should NOT run (ZFS was available)
    ! grep -q "install_dependencies" "$call_log"
}

# =============================================================================
# build() — prepare_kernel runs before configure_zfs_builtin (UTS_RELEASE needed)
# =============================================================================

@test "build calls prepare_kernel before configure_zfs_builtin" {
    export CI_BUILD=1

    local call_log="$TEST_TMPDIR/call_log"
    echo "" > "$call_log"

    install_dependencies() { echo "install_dependencies" >> "$call_log"; }
    get_kernel_src() { echo "get_kernel_src" >> "$call_log"; }
    prepare_kernel() { echo "prepare_kernel" >> "$call_log"; }
    get_zfs_builtin() { echo "get_zfs_builtin" >> "$call_log"; }
    configure_zfs_builtin() { echo "configure_zfs_builtin" >> "$call_log"; }
    build_kernel() { echo "build_kernel" >> "$call_log"; }

    run build

    [ "$status" -eq 0 ]
    # prepare_kernel MUST be called (ZFS configure needs UTS_RELEASE from make prepare)
    grep -q "prepare_kernel" "$call_log"
    # Verify ordering: prepare_kernel before get_zfs_builtin before configure_zfs_builtin
    local prep_line=$(grep -n "prepare_kernel" "$call_log" | head -1 | cut -d: -f1)
    local zfs_line=$(grep -n "get_zfs_builtin" "$call_log" | head -1 | cut -d: -f1)
    local conf_line=$(grep -n "configure_zfs_builtin" "$call_log" | head -1 | cut -d: -f1)
    [ "$prep_line" -lt "$zfs_line" ]
    [ "$zfs_line" -lt "$conf_line" ]
}

# =============================================================================
# get_zfs_builtin() — default ZFS version
# =============================================================================

@test "get_zfs_builtin defaults to zfs-2.3.4 when ZFS_VERSION not set" {
    unset ZFS_VERSION
    export ZFSDIR="$TEST_TMPDIR/zfs"

    # Mock git clone to capture the branch argument
    git() {
        if [ "$1" = "clone" ]; then
            mkdir -p "$ZFSDIR"
            echo "CLONE_ARGS: $*" > "$TEST_TMPDIR/git_args"
            return 0
        fi
        command git "$@"
    }
    export -f git

    run get_zfs_builtin

    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/git_args" ]
    grep -q "zfs-2.3.4" "$TEST_TMPDIR/git_args"
}

@test "get_zfs_builtin respects ZFS_VERSION env var" {
    export ZFS_VERSION="zfs-2.2.8"
    export ZFSDIR="$TEST_TMPDIR/zfs"

    git() {
        if [ "$1" = "clone" ]; then
            mkdir -p "$ZFSDIR"
            echo "CLONE_ARGS: $*" > "$TEST_TMPDIR/git_args"
            return 0
        fi
        command git "$@"
    }
    export -f git

    run get_zfs_builtin

    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/git_args" ]
    grep -q "zfs-2.2.8" "$TEST_TMPDIR/git_args"
}
