#!/usr/bin/env bash
#
# Package a pmOS boot image: our freshly built kernel + the ramdisk and
# cmdline taken from an already-working reference image.
#
# The ramdisk must not be regenerated here. Its cmdline carries
# pmos_boot_uuid/pmos_root_uuid, and those have to keep matching the
# rootfs already written to the SD card or the initramfs will not find
# root. Reusing the reference image's ramdisk byte-for-byte is what
# keeps that true across kernel rebuilds.
#
# Usage: ./make-pmos-image.sh [reference.img] [output.img]

set -euo pipefail

KDIR="${KDIR:-$HOME/vibe-coding-projects/coding/linux-mainline-v30}"
OUT="$(cd "$(dirname "$0")" && pwd)/out"

REF="${1:-$OUT/boot-joan-pmos-display.img}"
DEST="${2:-$OUT/boot-joan-pmos-touch.img}"

IMAGE="$KDIR/arch/arm64/boot/Image.gz"
DTB="$KDIR/arch/arm64/boot/dts/qcom/msm8998-lge-joan.dtb"

[[ -f "$IMAGE" && -f "$DTB" ]] || { echo "kernel or dtb missing — build first" >&2; exit 1; }
[[ -f "$REF" ]] || { echo "reference image $REF not found" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# unpack_bootimg prints the header fields; keep them so the cmdline
# (and therefore the rootfs UUIDs) can be carried over verbatim.
unpack_bootimg --boot_img "$REF" --out "$WORK" > "$WORK/header.txt"
CMDLINE="$(sed -n 's/^command line args: //p' "$WORK/header.txt")"
[[ -n "$CMDLINE" ]] || { echo "could not read cmdline from $REF" >&2; exit 1; }

echo "reference : $REF"
echo "cmdline   : $CMDLINE"

# LG aboot boots Image.gz-dtb (appended DTB), base 0x0, pagesize 4096.
# ramdisk_offset 0x02000000 is required: aboot loads the ramdisk on top
# of kernels larger than 16 MiB at the default offset.
cat "$IMAGE" "$DTB" > "$WORK/Image.gz-dtb"

mkbootimg \
    --kernel "$WORK/Image.gz-dtb" \
    --ramdisk "$WORK/ramdisk" \
    --base 0x00000000 \
    --pagesize 4096 \
    --kernel_offset 0x00008000 \
    --ramdisk_offset 0x02000000 \
    --tags_offset 0x00000100 \
    --cmdline "$CMDLINE" \
    --output "$DEST"

echo
ls -la "$DEST"
echo "kernel  sha256: $(sha256sum "$WORK/Image.gz-dtb" | cut -d' ' -f1)"
echo "ramdisk sha256: $(sha256sum "$WORK/ramdisk" | cut -d' ' -f1)"
echo "image   sha256: $(sha256sum "$DEST" | cut -d' ' -f1)"
echo
echo "RAM boot only:  sudo -n fastboot boot $DEST"
