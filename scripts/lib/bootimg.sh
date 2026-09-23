# shellcheck shell=bash
# Shared helpers for the joan boot-image scripts. Source, don't execute:
#
#   . "$(dirname "$(readlink -f "$0")")/scripts/lib/bootimg.sh"
#
# Everything the LG aboot image format needs lives here once, so the
# builders cannot drift apart on an offset again.

# Repo root, whichever script sourced us.
JOAN_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JOAN_OUT="${JOAN_OUT:-$JOAN_REPO/out}"

# The original maintainers' layout, kept only as a fallback so their
# existing muscle memory still works. Anyone else sets KDIR.
JOAN_LEGACY_KDIR="$HOME/vibe-coding-projects/coding/linux-mainline-v30"

die() { echo "${0##*/}: $*" >&2; exit 1; }

need_tools() {
	local t
	for t in "$@"; do
		command -v "$t" >/dev/null 2>&1 || die "required tool '$t' not found in PATH"
	done
}

# Resolve the kernel build and set KIMAGE / KDTB.
#
# KDIR may be either the kernel source tree (in-tree build) or the O=
# build directory (out-of-tree build) -- both carry arch/arm64/boot/.
# Pass an explicit path as $1 to override KDIR.
resolve_kernel() {
	local kdir="${1:-${KDIR:-}}"
	if [[ -z "$kdir" ]]; then
		[[ -d "$JOAN_LEGACY_KDIR" ]] ||
			die "set KDIR to your kernel source tree or O= build directory"
		kdir="$JOAN_LEGACY_KDIR"
	fi
	KIMAGE="$kdir/arch/arm64/boot/Image.gz"
	KDTB="$kdir/arch/arm64/boot/dts/qcom/msm8998-lge-joan.dtb"
	[[ -f "$KIMAGE" && -f "$KDTB" ]] ||
		die "kernel or dtb missing under $kdir -- build Image.gz and dtbs first"
}

# LG aboot boots Image.gz-dtb (DTB appended), base 0x0, pagesize 4096.
# Values from LineageOS android_device_lge_joan-common BoardConfigCommon.mk.
# ramdisk_offset 0x02000000 is required: at the default offset aboot loads
# the ramdisk on top of any kernel larger than 16 MiB.
#
#   joan_mkbootimg <kernel> <ramdisk> <cmdline> <output>
joan_mkbootimg() {
	mkbootimg \
		--kernel "$1" \
		--ramdisk "$2" \
		--base 0x00000000 \
		--pagesize 4096 \
		--kernel_offset 0x00008000 \
		--ramdisk_offset "${RAMDISK_OFFSET:-0x02000000}" \
		--tags_offset 0x00000100 \
		--cmdline "$3" \
		--output "$4"
}

# Append the DTB the way aboot expects.  append_dtb <dest>
append_dtb() {
	cat "$KIMAGE" "$KDTB" > "$1"
}

# Unpack a boot image into <dir> (kernel, ramdisk) and set BOOT_CMDLINE.
# The reference cmdline carries pmos_boot_uuid/pmos_root_uuid, which must
# keep matching the rootfs on the SD card -- so it is always carried over
# verbatim, never regenerated.
#
#   unpack_image <boot.img> <dir>
unpack_image() {
	[[ -f "$1" ]] || die "boot image $1 not found"
	mkdir -p "$2"
	unpack_bootimg --boot_img "$1" --out "$2" > "$2/header.txt" 2>&1 ||
		die "unpack_bootimg failed on $1"
	BOOT_CMDLINE="$(sed -n 's/^command line args: //p' "$2/header.txt")"
	[[ -n "$BOOT_CMDLINE" ]] || die "could not read cmdline from $1"
}

# cpio newc + gzip -9, root-owned. pack_cpio <tree> <output.cpio.gz>
pack_cpio() {
	( cd "$1" && find . | cpio -o -H newc --owner=0:0 --quiet | gzip -9 ) > "$2"
}

# unpack_cpio <ramdisk.cpio.gz> <tree>
unpack_cpio() {
	mkdir -p "$2"
	( cd "$2" && zcat "$1" | cpio -idm --quiet )
}

sha() { sha256sum "$1" | cut -d' ' -f1; }
