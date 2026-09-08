#!/bin/sh

set -eu

case "$__BUILD_ARCH" in
amd64|aarch64)
        ;;
*)
        echo "Architecture $__BUILD_ARCH not supported" >&2
        exit 1
        ;;
esac

cd /staging/initramfs/fs || exit 1
cp -f /sources/init .

find . -print0 | cpio --null -ov --format=newc | gzip -9 > "/staging/initramfs-busybox-${__BUILD_ARCH}.cpio.gz"

if [ -d "/repo/stage" ]; then
        cp -f "/staging/initramfs-busybox-${__BUILD_ARCH}.cpio.gz" /repo/stage
        cp -f "/staging/bzImage-$__BUILD_ARCH" /repo/stage
fi
