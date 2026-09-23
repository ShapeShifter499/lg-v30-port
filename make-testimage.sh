#!/usr/bin/env bash
# Build a fastboot-bootable Android boot.img with the mainline kernel,
# joan DTB (appended) and the USB-gadget bring-up initramfs.
#
# Usage: ./make-testimage.sh [kernel-dir]
#   kernel-dir (or $KDIR): kernel source tree or O= build directory.
set -euo pipefail

. "$(dirname "$(readlink -f "$0")")/scripts/lib/bootimg.sh"
need_tools mkbootimg cpio gzip
resolve_kernel "${1:-}"
mkdir -p "$JOAN_OUT"

# initramfs
chmod +x "$JOAN_REPO/initramfs/root/init" "$JOAN_REPO/initramfs/root/bin/"*
pack_cpio "$JOAN_REPO/initramfs/root" "$JOAN_OUT/initramfs.cpio.gz"

append_dtb "$JOAN_OUT/Image.gz-dtb"

# androidboot.* args mirrored from the stock cmdline where they matter for
# mainline (usbcontroller name is cosmetic there, kept for parity).
joan_mkbootimg "$JOAN_OUT/Image.gz-dtb" "$JOAN_OUT/initramfs.cpio.gz" \
	"androidboot.hardware=joan panic=5 ignore_loglevel" \
	"$JOAN_OUT/boot-joan-mainline.img"

ls -la "$JOAN_OUT/boot-joan-mainline.img"
echo "Tethered test:  fastboot boot $JOAN_OUT/boot-joan-mainline.img"
echo "Recovery slot:  fastboot flash recovery $JOAN_OUT/boot-joan-mainline.img  (then Vol-Down+Power boot)"
echo "After boot: host side 'ip addr add 172.16.42.2/24 dev <usb-if>' then 'telnet 172.16.42.1'"
