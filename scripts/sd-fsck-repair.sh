#!/usr/bin/env bash
# joan SD card fsck — modern e2fsck (from the pmOS initramfs) run from
# LineageOS via adb root against the pmOS rootfs partition.
#
# WHY: LineageOS ships e2fsck 1.46.2, which bails on the newer ext4
# features of the pmOS rootfs (its "still has errors" means "could not
# check"). The pmOS initramfs carries e2fsck 1.47.4 (Alpine musl); this
# script extracts it + loader + libs, pushes them to /data/local/tmp,
# and runs them with the musl loader. Full runbook:
# docs/sd-card-fsck-and-recovery.md
#
# MODES:
#   check   (default)  e2fsck -fn — READ-ONLY, safe any time, no auth.
#   repair              preen + full -fy — PERSISTENT WRITE to the
#                      rootfs. Requires Lance present + approving and
#                      AUTH=yes-i-have-owner-authorization.
#
# USAGE:
#   RD=/path/to/unpacked-initramfs scripts/sd-fsck-repair.sh [check|repair]
#   IMG=/path/to/boot.img scripts/sd-fsck-repair.sh [check|repair]
#
# Env: HOST   -- ssh host the phone is plugged into; empty (default) means
#               the phone is on this machine and adb runs locally.
#      SERIAL -- adb serial to target; empty (default) = the only device.
#      DEV    -- default /dev/block/mmcblk0p2.
set -uo pipefail

HOST="${HOST:-}"
SERIAL="${SERIAL:-}"
DEV="${DEV:-/dev/block/mmcblk0p2}"
RD="${RD:-}"
IMG="${IMG:-}"
MODE="${1:-check}"
AUTH="${AUTH:-}"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

ADB="adb${SERIAL:+ -s $SERIAL}"
# Run a shell snippet on the machine the phone is attached to.
on_host() {
  if [ -n "$HOST" ]; then ssh -o ConnectTimeout=15 "$HOST" "$1"; else bash -c "$1"; fi
}
# Make a local file available on that machine as <name>; prints its path.
STAGE="$WORK/stage"; mkdir -p "$STAGE"
stage() {
  if [ -n "$HOST" ]; then
    scp -o ConnectTimeout=15 "$1" "$HOST:/tmp/$2" >/dev/null 2>&1 || return 1
    echo "/tmp/$2"
  else
    cp "$1" "$STAGE/$2" && echo "$STAGE/$2"
  fi
}

case "$MODE" in
  check)  ;;
  repair)
    [ "$AUTH" = "yes-i-have-owner-authorization" ] || {
      echo "REPAIR_REFUSED: persistent write to the pmOS rootfs — Lance must be"
      echo "present and approving. Re-run with AUTH=yes-i-have-owner-authorization." >&2
      exit 3; }
    ;;
  *) echo "usage: $0 [check|repair]" >&2; exit 2 ;;
esac

# --- 0. locate the initramfs e2fsck -------------------------------------
if [ -z "$RD" ]; then
  [ -n "$IMG" ] || { echo "RD= or IMG= required" >&2; exit 2; }
  unpack_bootimg --boot_img "$IMG" --out "$WORK/img" >/dev/null 2>&1 \
    || { echo "unpack_bootimg failed" >&2; exit 2; }
  mkdir -p "$WORK/rd"
  ( cd "$WORK/rd" && zcat "$WORK/img/ramdisk" | cpio -idm --quiet ) \
    || { echo "ramdisk unpack failed" >&2; exit 2; }
  RD="$WORK/rd"
fi
[ -x "$RD/sbin/e2fsck" ] || { echo "no sbin/e2fsck under $RD" >&2; exit 2; }
[ -f "$RD/lib/ld-musl-aarch64.so.1" ] || { echo "no musl loader under $RD" >&2; exit 2; }

# --- 1. phone side prep (adb root, stage dirs) --------------------------
echo "=== DEVICE PREP ==="
on_host "
  $ADB root >/dev/null 2>&1; sleep 2; $ADB wait-for-device
  $ADB shell 'mkdir -p /data/local/tmp/musl/lib /data/local/tmp/musl/usr/lib'
  $ADB shell 'cat /proc/partitions | grep mmcblk'
" || { echo "DEVICE_PREP_FAILED" >&2; exit 4; }

# --- 2. stage on host, push to device ------------------------------------
echo "=== PUSH e2fsck + loader + libs ==="
LIBS="libext2fs.so.2 libcom_err.so.2 libblkid.so.1 libuuid.so.1 libe2p.so.2 libc.musl-aarch64.so.1 libeconf.so.0"
e2fsck_src="$(stage "$RD/sbin/e2fsck" e2fsck-modern)" || { echo "STAGE_FAILED" >&2; exit 4; }
musl_src="$(stage "$RD/lib/ld-musl-aarch64.so.1" ld-musl.so)" || { echo "STAGE_FAILED" >&2; exit 4; }
PUSH="$ADB push $e2fsck_src /data/local/tmp/e2fsck 2>&1 | tail -1
  $ADB push $musl_src /data/local/tmp/musl/lib/ld-musl-aarch64.so.1 2>&1 | tail -1"
for l in $LIBS; do
  f="$(find "$RD" -name "$l*" 2>/dev/null | head -1)"
  [ -n "$f" ] || { echo "MISSING $l in ramdisk" >&2; exit 2; }
  src="$(stage "$f" "lib-$l")" || { echo "STAGE_FAILED" >&2; exit 4; }
  PUSH="$PUSH
  $ADB push $src /data/local/tmp/musl/usr/lib/$l 2>&1 | tail -1"
done
on_host "
  $PUSH
  $ADB shell 'chmod 755 /data/local/tmp/e2fsck /data/local/tmp/musl/lib/ld-musl-aarch64.so.1'
  $ADB shell '/data/local/tmp/musl/lib/ld-musl-aarch64.so.1 --library-path /data/local/tmp/musl/usr/lib /data/local/tmp/e2fsck -V 2>&1 | head -1'
" || { echo "PUSH_FAILED" >&2; exit 4; }

# --- 3. run --------------------------------------------------------------
[ "$MODE" = "repair" ] && {
  echo "=== MOUNT GUARD ==="
  mnt="$(on_host "$ADB shell 'mount | grep -c $DEV' | tr -d '\r'")"
  [ "${mnt:-0}" = "0" ] || { echo "REFUSED: $DEV is mounted; unmount it first" >&2; exit 5; }
  echo "not mounted, ok"
}

echo "=== FSCK ($MODE) on $DEV ==="
RUN="/data/local/tmp/musl/lib/ld-musl-aarch64.so.1 --library-path /data/local/tmp/musl/usr/lib /data/local/tmp/e2fsck"
if [ "$MODE" = "check" ]; then
  on_host "$ADB shell '$RUN -fn $DEV; echo E2FSCK_RC=\$?'" \
    || { echo "FSCK_CHECK_FAILED" >&2; exit 4; }
else
  on_host "$ADB shell '$RUN -p $DEV; echo PREEN_RC=\$?; $RUN -fy $DEV; echo FULL_RC=\$?'" \
    || { echo "FSCK_REPAIR_FAILED" >&2; exit 4; }
fi

echo
echo "=== INTERPRETATION ==="
echo "e2fsck rc: 0 = clean, 1 = errors corrected, 2 = corrected+reboot needed,"
echo "           >= 4 = uncorrected — investigate; hard read errors mid-scan"
echo "           mean the card itself needs replacement/reimage."
[ "$MODE" = "repair" ] && cat <<'EOF'
=== ORPHAN REMINDER ===
A full pass can orphan inconsistent trees (2026-08-05: /home/user) into
/lost+found. Restoring anything into the pmOS rootfs is a persistent
write — get Lance's authorization first, and verify /home/user exists
before relying on the install.
EOF
echo "SD_FSCK_${MODE}_DONE"
