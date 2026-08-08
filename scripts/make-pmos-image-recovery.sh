#!/usr/bin/env bash
# Build a recovery-patched boot image from a sealed source image.
# Kernel + DTB stay byte-identical to the source; only the initramfs
# is patched (self-healing boot-stage waits). Also verifies the patch
# markers exist in the final image's ramdisk.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:?usage: $0 <source-boot.img> <dest-boot.img>}"
DEST="${2:?usage: $0 <source-boot.img> <dest-boot.img>}"
PATCHER="$HERE/patch-initramfs-recovery.sh"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
unpack_bootimg --boot_img "$SRC" --out "$WORK" > "$WORK/header.txt" 2>&1
CMDLINE="$(sed -n 's/^command line args: //p' "$WORK/header.txt")"
[[ -n "$CMDLINE" ]] || { echo "could not read cmdline" >&2; exit 1; }

mkdir -p "$WORK/rd"
( cd "$WORK/rd" && zcat "$WORK/ramdisk" | cpio -idm --quiet )

bash "$PATCHER" "$WORK/rd"

( cd "$WORK/rd" && find . | cpio -o -H newc --owner=0:0 --quiet | gzip -9 ) > "$WORK/ramdisk.new"

mkbootimg \
    --kernel "$WORK/kernel" \
    --ramdisk "$WORK/ramdisk.new" \
    --base 0x00000000 --pagesize 4096 \
    --kernel_offset 0x00008000 --ramdisk_offset 0x02000000 \
    --tags_offset 0x00000100 \
    --cmdline "$CMDLINE" \
    --output "$DEST"

echo "=== verify final image ramdisk has the patches ==="
VW="$(mktemp -d)"; trap 'rm -rf "$WORK" "$VW"' EXIT
unpack_bootimg --boot_img "$DEST" --out "$VW" > /dev/null 2>&1
mkdir -p "$VW/rd"
( cd "$VW/rd" && zcat "$VW/ramdisk" | cpio -idm --quiet )
grep -c 'fsck repair wait timed out' "$VW/rd/init_functions.sh"
grep -c 'Debug shell timed out' "$VW/rd/init_functions.sh"
grep -c 'rebooting to persistent OS' "$VW/rd/init_functions.sh"

echo "=== kernel identity preserved ==="
sha256sum "$WORK/kernel" "$VW/kernel"
echo "=== cmdline ==="
echo "$CMDLINE"
echo "=== image ==="
sha256sum "$DEST"
echo BUILD_OK
