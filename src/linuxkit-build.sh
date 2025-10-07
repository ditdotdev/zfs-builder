#!/bin/bash
#
# Copyright The Titan Project Contributors.
#

set -xe

. $(dirname $0)/common.sh

# Get ZFS source first, then build with proper kernel paths
get_zfs_source
build_zfs