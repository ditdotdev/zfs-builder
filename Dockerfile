#
# Copyright Dit 2026
# SPDX-License-Identifier: BUSL-1.1
#

# Used to create ditdotdev/zfs-builder:latest. Until we update Docker Hub, use this locally to build ditdotdev/zfs-builder:latest container.

FROM ubuntu:26.04

ARG KERNEL_RELEASE=
ARG KERNEL_UNAME=
ARG ZFS_VERSION=

# Single consolidated install: enable universe, then install every build
# dependency the image needs (ZFS userland + module compile, Python helpers,
# kernel build + WSL2 custom-kernel tools, Docker repo prerequisites).
# Collapsed into one RUN to keep the layer graph small per DL3059, with
# --no-install-recommends per DL3015 and apt list cleanup per DL3009.
RUN apt-get update \
    && apt-get install -y --no-install-recommends software-properties-common \
    && add-apt-repository universe \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        curl \
        xz-utils \
        jq \
        build-essential \
        bc \
        autoconf \
        automake \
        libtool \
        kmod \
        zlib1g-dev \
        uuid-dev \
        libattr1-dev \
        libblkid-dev \
        libselinux-dev \
        libudev-dev \
        libacl1-dev \
        libaio-dev \
        libdevmapper-dev \
        libssl-dev \
        libelf-dev \
        python3 \
        python3-dev \
        python3-setuptools \
        libarchive-tools \
        libncurses-dev \
        bison \
        flex \
        dwarves \
        python3-cffi \
        libtirpc-dev \
        libffi-dev \
        apt-transport-https \
        ca-certificates \
        gnupg2 \
    && rm -rf /var/lib/apt/lists/*

# Add Docker apt repository and install docker-ce-cli. Separate RUN because
# the apt source has to exist before the install step can resolve the package.
# `. /etc/os-release` sources a runtime file we can't lint statically;
# SC1091 is globally ignored via .hadolint.yaml.
RUN install -m 0755 -d /etc/apt/keyrings \
    && . /etc/os-release \
    && curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir /src /build /out

COPY src/* /

CMD ["/build.sh"]
