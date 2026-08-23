#!/bin/sh
# Provisions a stock ubuntu:20.04, then builds and contract-checks the core there.
set -eux
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
apt-get update -qq
# shellcheck disable=SC2086
apt-get install -y -qq $DEBIAN_DEPS ninja-build libarchive-tools \
    python3 python3-pip curl ca-certificates bzip2 xz-utils
# focal's cmake and meson predate what the package client needs.
pip3 install --quiet cmake==3.31.6 meson==1.11.0
if [ -x /usr/sbin/update-ccache-symlinks ]; then
    /usr/sbin/update-ccache-symlinks
fi
export PATH=/usr/lib/ccache:$PATH
git config --global user.email "builds@ci.invalid"
git config --global user.name "CI"
git config --global --add safe.directory '*'
mkdir -p build
cd build
cmake .. -DVITASDK_STAGE1_DIR="$STAGE1_DIR" \
    -DBUILD_PACMAN_CLIENT=ON \
    -DPACMAN_CLIENT_INSTALL_DIR="$PWD/vitasdk" \
    -DVITASDK_SOURCE_REVISION="$VITASDK_SOURCE_REVISION" \
    -DVITASDK_SOURCE_DATE_EPOCH="$VITASDK_SOURCE_DATE_EPOCH" \
    -DVDPM_BUNDLE="$VDPM_BUNDLE" \
    -DVDPM_BUNDLE_SHA256="$VDPM_BUNDLE_SHA256"
make -j"$(nproc)" tarball core-package bootstrap-archive
make check-toolchain-contract
