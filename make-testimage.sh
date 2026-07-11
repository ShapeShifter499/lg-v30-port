#!/usr/bin/env bash
# Build a fastboot-bootable Android boot.img with the mainline kernel,
# joan DTB (appended) and the USB-gadget bring-up initramfs.
#
# Usage: ./make-testimage.sh [kernel-tree]   (default: coding/linux-mainline-v30)
set -euo pipefail

HERE="$(dirname "$(readlink -f "$0")")"
KDIR="${1:-$HOME/vibe-coding-projects/coding/linux-mainline-v30}"
OUT="$HERE/out"
mkdir -p "$OUT"

IMAGE="$KDIR/arch/arm64/boot/Image.gz"
DTB="$KDIR/arch/arm64/boot/dts/qcom/msm8998-lge-joan.dtb"
[[ -f "$IMAGE" && -f "$DTB" ]] || { echo "kernel or dtb missing — build first" >&2; exit 1; }

# initramfs
( cd "$HERE/initramfs/root" && chmod +x init bin/busybox && \
  find . | cpio -o -H newc --owner=0:0 | gzip -9 ) > "$OUT/initramfs.cpio.gz"

# LG aboot boots Image.gz-dtb (appended DTB), base 0x0, pagesize 4096
cat "$IMAGE" "$DTB" > "$OUT/Image.gz-dtb"

# Values from LineageOS android_device_lge_joan-common BoardConfigCommon.mk;
# androidboot.* args mirrored from the stock cmdline where they matter for
# mainline (usbcontroller name is cosmetic there, kept for parity).
mkbootimg \
    --kernel "$OUT/Image.gz-dtb" \
    --ramdisk "$OUT/initramfs.cpio.gz" \
    --base 0x00000000 \
    --pagesize 4096 \
    --ramdisk_offset 0x02000000 \
    --cmdline "androidboot.hardware=joan panic=5 ignore_loglevel" \
    --output "$OUT/boot-joan-mainline.img"

ls -la "$OUT/boot-joan-mainline.img"
echo "Tethered test:  fastboot boot $OUT/boot-joan-mainline.img"
echo "Recovery slot:  fastboot flash recovery $OUT/boot-joan-mainline.img  (then Vol-Down+Power boot)"
echo "After boot: host side 'ip addr add 172.16.42.2/24 dev <usb-if>' then 'telnet 172.16.42.1'"
