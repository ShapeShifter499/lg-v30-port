#!/usr/bin/env bash
#
# Legacy standalone-image helper. The preferred postmarketOS path is the
# firmware-qcom-adreno-a530 + firmware-lge-joan package split; this helper
# injects the same exact file set into an already-built reference initramfs.
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
A530_FW_DIR="${A530_FW_DIR:-}"
A540_FW_DIR="${A540_FW_DIR:-$HERE/firmware/zap}"

[[ -n "$A530_FW_DIR" ]] || {
    printf '%s\n' \
        "A530_FW_DIR is required; point it at lib/firmware/qcom extracted" \
        "from the official postmarketOS firmware-qcom-adreno-a530 package" >&2
    exit 1
}

# A540 reuses the public A530 PM4/PFP command firmware. The GPMU and signed LG
# ZAP payload are separate owner-extracted joan inputs.
required_fw=(
    "$A530_FW_DIR/a530_pfp.fw"
    "$A530_FW_DIR/a530_pm4.fw"
    "$A540_FW_DIR/a540_gpmu.fw2"
    "$A540_FW_DIR/a540_zap.mdt"
    "$A540_FW_DIR/a540_zap.b00"
    "$A540_FW_DIR/a540_zap.b01"
    "$A540_FW_DIR/a540_zap.b02"
)
for f in "${required_fw[@]}"; do
    [[ -s "$f" ]] || {
        echo "required GPU firmware missing or empty: $f" >&2
        exit 1
    }
done

IMAGE="$KDIR/arch/arm64/boot/Image.gz"
DTB="$KDIR/arch/arm64/boot/dts/qcom/msm8998-lge-joan.dtb"
[[ -f "$IMAGE" && -f "$DTB" ]] || { echo "kernel or dtb missing" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
unpack_bootimg --boot_img "$REF" --out "$WORK" > "$WORK/header.txt"
CMDLINE="$(sed -n 's/^command line args: //p' "$WORK/header.txt")"
[[ -n "$CMDLINE" ]] || { echo "could not read cmdline" >&2; exit 1; }

# Appended verbatim after the reference cmdline, so pmos_boot_uuid/pmos_root_uuid
# are untouched. Used to set module params on a device we have no root on.
if [[ -n "${EXTRA_CMDLINE:-}" ]]; then
    CMDLINE="$CMDLINE $EXTRA_CMDLINE"
fi

mkdir -p "$WORK/rd"
( cd "$WORK/rd" && zcat "$WORK/ramdisk" | cpio -idm --quiet )

mkdir -p "$WORK/rd/lib/firmware/qcom"

# The ramdisk is a disposable unpack tree.  Do not mix a prior image's A5xx
# payload with the exact set being qualified for this image.
rm -f "$WORK/rd/lib/firmware/qcom"/a530_* \
      "$WORK/rd/lib/firmware/qcom"/a540_*
for f in "${required_fw[@]}"; do
    install -m 0644 "$f" "$WORK/rd/lib/firmware/qcom/"
done

echo "firmware injected (SHA-256):"
for f in "$WORK/rd/lib/firmware/qcom"/a530_* \
         "$WORK/rd/lib/firmware/qcom"/a540_*; do
    sha256sum "$f"
done

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
