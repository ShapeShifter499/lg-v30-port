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
# Usage: KDIR=<kernel-dir> ./make-pmos-image.sh [reference.img] [output.img]
#   KDIR: kernel source tree or O= build directory.
#
# Before booting the result, compare its size with the family of images
# already known to boot: a kernel ~1 MB light means a lost .config, not a
# code change (docs/ember-2026-08-10-unpin-result-was-confounded.md).

set -euo pipefail

. "$(dirname "$(readlink -f "$0")")/scripts/lib/bootimg.sh"
need_tools mkbootimg unpack_bootimg
resolve_kernel

REF="${1:-$JOAN_OUT/boot-joan-pmos-display.img}"
DEST="${2:-$JOAN_OUT/boot-joan-pmos-touch.img}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

unpack_image "$REF" "$WORK"
echo "reference : $REF"
echo "cmdline   : $BOOT_CMDLINE"

append_dtb "$WORK/Image.gz-dtb"
joan_mkbootimg "$WORK/Image.gz-dtb" "$WORK/ramdisk" "$BOOT_CMDLINE" "$DEST"

echo
ls -la "$DEST"
echo "kernel  sha256: $(sha "$WORK/Image.gz-dtb")"
echo "ramdisk sha256: $(sha "$WORK/ramdisk")"
echo "image   sha256: $(sha "$DEST")"
echo
echo "RAM boot only:  sudo -n fastboot boot $DEST"
