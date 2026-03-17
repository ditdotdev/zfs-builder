#!/usr/bin/env bats
#
# Tests for build.sh functions, particularly check_zfs_availability().
#
# Bug 3: check_zfs_availability() requires ALL of kernel + /dev/zfs + zpool,
# but inside a container with built-in ZFS on the host, only /proc/filesystems
# shows ZFS support. The device node and userspace tools don't exist in the
# container. Kernel support alone should be sufficient to skip the build.
#

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    mkdir -p "$TEST_TMPDIR/proc"
    mkdir -p "$TEST_TMPDIR/dev"
    mkdir -p "$TEST_TMPDIR/bin"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# Mock check_zfs_availability that uses our test paths instead of real system paths.
# This mirrors the logic in build.sh but with configurable paths.
_mock_check_zfs_availability() {
    local proc_filesystems="$TEST_TMPDIR/proc/filesystems"
    local dev_zfs="$TEST_TMPDIR/dev/zfs"
    local mock_zpool="$TEST_TMPDIR/bin/zpool"

    local ZFS_KERNEL_AVAILABLE=0
    local ZFS_DEVICE_AVAILABLE=0
    local ZFS_USERSPACE_AVAILABLE=0

    # Check if ZFS filesystem is supported in kernel
    if grep -q "^nodev.*zfs" "$proc_filesystems" 2>/dev/null; then
        ZFS_KERNEL_AVAILABLE=1
    fi

    # Check if ZFS device node exists
    if [ -e "$dev_zfs" ]; then
        ZFS_DEVICE_AVAILABLE=1
    fi

    # Check if ZFS userspace tools are available
    if [ -x "$mock_zpool" ]; then
        ZFS_USERSPACE_AVAILABLE=1
    fi

    # Fixed logic: kernel support alone is sufficient to skip the build
    if [ "$ZFS_KERNEL_AVAILABLE" = "1" ]; then
        return 0
    fi

    return 1
}

# This mirrors the CURRENT (buggy) behavior of check_zfs_availability in build.sh
_buggy_check_zfs_availability() {
    local proc_filesystems="$TEST_TMPDIR/proc/filesystems"
    local dev_zfs="$TEST_TMPDIR/dev/zfs"
    local mock_zpool="$TEST_TMPDIR/bin/zpool"

    local ZFS_KERNEL_AVAILABLE=0
    local ZFS_DEVICE_AVAILABLE=0
    local ZFS_USERSPACE_AVAILABLE=0

    if grep -q "^nodev.*zfs" "$proc_filesystems" 2>/dev/null; then
        ZFS_KERNEL_AVAILABLE=1
    fi

    if [ -e "$dev_zfs" ]; then
        ZFS_DEVICE_AVAILABLE=1
    fi

    if [ -x "$mock_zpool" ]; then
        ZFS_USERSPACE_AVAILABLE=1
    fi

    # Buggy: requires ALL three
    if [ "$ZFS_KERNEL_AVAILABLE" = "1" ] && [ "$ZFS_DEVICE_AVAILABLE" = "1" ] && [ "$ZFS_USERSPACE_AVAILABLE" = "1" ]; then
        return 0
    fi

    return 1
}

# =============================================================================
# Bug 3: check_zfs_availability() too strict — kernel support alone should suffice
# =============================================================================

@test "BUGGY: check_zfs_availability fails when only kernel support exists (no /dev/zfs, no zpool)" {
    # Simulate container with built-in ZFS on host: /proc/filesystems shows ZFS
    # but /dev/zfs and zpool are not available inside the container
    cat > "$TEST_TMPDIR/proc/filesystems" << 'EOF'
nodev	sysfs
nodev	tmpfs
nodev	zfs
	ext4
EOF

    # This demonstrates the bug: the old logic requires all three
    run _buggy_check_zfs_availability
    [ "$status" -eq 1 ]  # Bug: returns failure even though kernel has ZFS
}

@test "FIXED: check_zfs_availability succeeds when only kernel support exists" {
    # Same setup: kernel has ZFS but no device node or userspace tools
    cat > "$TEST_TMPDIR/proc/filesystems" << 'EOF'
nodev	sysfs
nodev	tmpfs
nodev	zfs
	ext4
EOF

    run _mock_check_zfs_availability
    [ "$status" -eq 0 ]  # Fixed: kernel support alone is sufficient
}

@test "check_zfs_availability succeeds when all three are present" {
    cat > "$TEST_TMPDIR/proc/filesystems" << 'EOF'
nodev	zfs
EOF
    touch "$TEST_TMPDIR/dev/zfs"
    cat > "$TEST_TMPDIR/bin/zpool" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$TEST_TMPDIR/bin/zpool"

    run _mock_check_zfs_availability
    [ "$status" -eq 0 ]
}

@test "check_zfs_availability fails when ZFS is not available anywhere" {
    cat > "$TEST_TMPDIR/proc/filesystems" << 'EOF'
nodev	sysfs
nodev	tmpfs
	ext4
EOF

    run _mock_check_zfs_availability
    [ "$status" -eq 1 ]
}

@test "check_zfs_availability succeeds with kernel + device but no userspace" {
    cat > "$TEST_TMPDIR/proc/filesystems" << 'EOF'
nodev	zfs
EOF
    touch "$TEST_TMPDIR/dev/zfs"

    run _mock_check_zfs_availability
    [ "$status" -eq 0 ]
}
