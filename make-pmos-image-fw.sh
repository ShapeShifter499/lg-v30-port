#!/usr/bin/env bash
#
# Like make-pmos-image.sh, but injects GPU firmware into the initramfs.
#
# The GPU driver requests firmware during early probe (t~1.3s), long before
# the SD rootfs is mounted (t~7.4s), so firmware installed to the rootfs is
# never found. It has to be in the initramfs.
#
# The reference image's cmdline is still carried over verbatim, so the
# pmos_boot_uuid/pmos_root_uuid continue to match the rootfs on the card.
set -euo pipefail

KDIR="${KDIR:-$HOME/vibe-coding-projects/coding/linux-mainline-v30}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"
REF="${1:-$OUT/boot-joan-pmos-touch.img}"
DEST="${2:-$OUT/boot-joan-pmos-fw.img}"
FWSRC="${FWSRC:-$HERE/firmware/zap}"
FWSRC2="${FWSRC2:-$HERE/initramfs/root/lib/firmware/qcom}"

IMAGE="$KDIR/arch/arm64/boot/Image.gz"
DTB="$KDIR/arch/arm64/boot/dts/qcom/msm8998-lge-joan.dtb"
[[ -f "$IMAGE" && -f "$DTB" ]] || { echo "kernel or dtb missing" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
unpack_bootimg --boot_img "$REF" --out "$WORK" > "$WORK/header.txt"
CMDLINE="$(sed -n 's/^command line args: //p' "$WORK/header.txt")"
[[ -n "$CMDLINE" ]] || { echo "could not read cmdline" >&2; exit 1; }

mkdir -p "$WORK/rd"
( cd "$WORK/rd" && zcat "$WORK/ramdisk" | cpio -idm --quiet )

mkdir -p "$WORK/rd/lib/firmware/qcom"
for f in "$FWSRC"/a540_* "$FWSRC2"/a530_*; do
    [[ -f "$f" ]] && install -m 0644 "$f" "$WORK/rd/lib/firmware/qcom/"
done
echo "firmware injected:"
ls -1 "$WORK/rd/lib/firmware/qcom/" | sed 's/^/    /'

( cd "$WORK/rd" && find . | cpio -o -H newc --owner=0:0 --quiet | gzip -9 ) > "$WORK/ramdisk.new"

cat "$IMAGE" "$DTB" > "$WORK/Image.gz-dtb"
mkbootimg \
    --kernel "$WORK/Image.gz-dtb" \
    --ramdisk "$WORK/ramdisk.new" \
    --base 0x00000000 --pagesize 4096 \
    --kernel_offset 0x00008000 --ramdisk_offset 0x02000000 \
    --tags_offset 0x00000100 \
    --cmdline "$CMDLINE" \
    --output "$DEST"

echo
echo "cmdline  : $CMDLINE"
echo "ramdisk  : $(stat -c%s "$WORK/ramdisk") -> $(stat -c%s "$WORK/ramdisk.new") bytes"
echo "image    : $(sha256sum "$DEST" | cut -d' ' -f1)"
