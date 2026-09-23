#!/usr/bin/env bash
# Build a recovery-patched boot image from a sealed source image.
# Kernel + DTB stay byte-identical to the source; only the initramfs
# is patched (self-healing boot-stage waits, see
# patch-initramfs-recovery.sh). Also verifies the patch markers exist in
# the final image's ramdisk.
#
# Usage: scripts/make-pmos-image-recovery.sh <source-boot.img> <dest-boot.img>
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
. "$HERE/lib/bootimg.sh"
need_tools mkbootimg unpack_bootimg cpio gzip python3

SRC="${1:?usage: $0 <source-boot.img> <dest-boot.img>}"
DEST="${2:?usage: $0 <source-boot.img> <dest-boot.img>}"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
unpack_image "$SRC" "$WORK/src"
unpack_cpio "$WORK/src/ramdisk" "$WORK/rd"

bash "$HERE/patch-initramfs-recovery.sh" "$WORK/rd"

pack_cpio "$WORK/rd" "$WORK/ramdisk.new"
joan_mkbootimg "$WORK/src/kernel" "$WORK/ramdisk.new" "$BOOT_CMDLINE" "$DEST"

echo "=== verify final image ramdisk has the patches ==="
unpack_image "$DEST" "$WORK/verify"
unpack_cpio "$WORK/verify/ramdisk" "$WORK/verify/rd"
for marker in 'fsck repair wait timed out' 'Debug shell timed out' 'rebooting to persistent OS'; do
	grep -q "$marker" "$WORK/verify/rd/init_functions.sh" ||
		die "patch marker missing from final image: $marker"
	echo "  present: $marker"
done

echo "=== kernel identity preserved ==="
[[ "$(sha "$WORK/src/kernel")" == "$(sha "$WORK/verify/kernel")" ]] ||
	die "kernel changed during repack"
sha256sum "$WORK/src/kernel" "$WORK/verify/kernel"
echo "=== cmdline ==="
echo "$BOOT_CMDLINE"
echo "=== image ==="
sha256sum "$DEST"
echo BUILD_OK
