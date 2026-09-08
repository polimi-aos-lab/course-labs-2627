#!/bin/sh

set -eu

JOBS="${BUILD_JOBS:-4}"

if [ "$__BUILD_ARCH" = "amd64" ]; then 
        # df_file=x86_64_defconfig 
        im_file=bzImage
        im_file_path=/sources/linux/arch/x86_64/boot/bzImage
elif [ "$__BUILD_ARCH" = "aarch64" ]; then 
        # df_file=defconfig 
        im_file=Image
        im_file_path=/sources/linux/arch/arm64/boot/Image
else 
	echo "Architecture $__BUILD_ARCH not supported"
	exit 1
fi

mkdir -p /staging/initramfs/fs

cd /sources/linux || exit 1
# make ${df_file} // now we use a .config stored in the repo
make -j"$JOBS" "${im_file}"

# build busybox
cd /sources/busybox-1.32.1 || exit 1
make defconfig
LDFLAGS="--static" make -j"$JOBS" install
cp -f "$im_file_path" "/staging/bzImage-$__BUILD_ARCH"

mkdir -p /staging/initramfs/fs

cd /staging/initramfs/fs || exit 1
mkdir -pv bin sbin etc proc sys usr/bin usr/sbin
cp -afv /sources/busybox-1.32.1/_install/* .
cp -f /sources/init .

if [ ! -f "/staging/initramfs/fs/bin/perf" ]; then
        cd /sources/linux/tools/perf || exit 1
        LDFLAGS=-static NO_LIBPYTHON=1 make
        cp -f perf /staging/initramfs/fs/bin
fi

find . -print0 | cpio --null -ov --format=newc | gzip -9 > "/staging/initramfs-busybox-${__BUILD_ARCH}.cpio.gz"

if [ -d "/repo/stage" ]; then
        cp -f "/staging/initramfs-busybox-${__BUILD_ARCH}.cpio.gz" /repo/stage
        cp -f "/staging/bzImage-$__BUILD_ARCH" /repo/stage
fi
