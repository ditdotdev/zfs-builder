#!/bin/bash
#
# Copyright The Titan Project Contributors.
# Modifications Copyright Dit 2026.
# SPDX-License-Identifier: BUSL-1.1
# Portions derived from titan-data/zfs-builder (Apache-2.0); see licenses/Apache-2.0.txt.
#

set -xe

# shellcheck source=src/common.sh
. "$(dirname "$0")/common.sh"

#
# This script is invoked within the context of the centos container, so  we can
# execute native yum commands.
#
CENTOS_KERNEL=${KERNEL_RELEASE%%.x86_64}

yum install -y "kernel-devel-$CENTOS_KERNEL" "kernel-$CENTOS_KERNEL"

# KERNEL_SRC / KERNEL_OBJ are consumed by build_zfs() in common.sh
# shellcheck disable=SC2034
KERNEL_SRC=/usr/src/kernels/$KERNEL_RELEASE
# shellcheck disable=SC2034
KERNEL_OBJ=/lib/modules/$KERNEL_RELEASE/build

get_zfs_source
build_zfs
