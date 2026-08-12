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
# Env: HOST (default nym-nest-family), SERIAL (default LGUS9986e606d55),
# DEV (default /dev/block/mmcblk0p2).
set -uo pipefail

HOST="${HOST:-nym-nest-family}"
SERIAL="${SERIAL:-LGUS9986e606d55}"
DEV="${DEV:-/dev/block/mmcblk0p2}"
RD="${RD:-}"
IMG="${IMG:-}"
MODE="${1:-check}"
AUTH="${AUTH:-}"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

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
ssh -o ConnectTimeout=15 "$HOST" "
  adb -s $SERIAL root >/dev/null 2>&1; sleep 2; adb -s $SERIAL wait-for-device
  adb -s $SERIAL shell 'mkdir -p /data/local/tmp/musl/lib /data/local/tmp/musl/usr/lib'
  adb -s $SERIAL shell 'cat /proc/partitions | grep mmcblk'
" || { echo "DEVICE_PREP_FAILED" >&2; exit 4; }

# --- 2. stage on host, push to device ------------------------------------
echo "=== PUSH e2fsck + loader + libs ==="
scp -o ConnectTimeout=15 "$RD/sbin/e2fsck" "$HOST:/tmp/e2fsck-modern" >/dev/null 2>&1
scp -o ConnectTimeout=15 "$RD/lib/ld-musl-aarch64.so.1" "$HOST:/tmp/ld-musl.so" >/dev/null 2>&1
for l in libext2fs.so.2 libcom_err.so.2 libblkid.so.1 libuuid.so.1 \
         libe2p.so.2 libc.musl-aarch64.so.1 libeconf.so.0; do
  f="$(find "$RD" -name "$l*" 2>/dev/null | head -1)"
  [ -n "$f" ] || { echo "MISSING $l in ramdisk" >&2; exit 2; }
  scp -o ConnectTimeout=15 "$f" "$HOST:/tmp/lib-$l" >/dev/null 2>&1
done
ssh -o ConnectTimeout=15 "$HOST" "
  adb -s $SERIAL push /tmp/e2fsck-modern /data/local/tmp/e2fsck 2>&1 | tail -1
  adb -s $SERIAL push /tmp/ld-musl.so /data/local/tmp/musl/lib/ld-musl-aarch64.so.1 2>&1 | tail -1
  for l in libext2fs.so.2 libcom_err.so.2 libblkid.so.1 libuuid.so.1 libe2p.so.2 libc.musl-aarch64.so.1 libeconf.so.0; do
    adb -s $SERIAL push /tmp/lib-\$l /data/local/tmp/musl/usr/lib/\$l 2>&1 | tail -1
  done
  adb -s $SERIAL shell 'chmod 755 /data/local/tmp/e2fsck /data/local/tmp/musl/lib/ld-musl-aarch64.so.1'
  adb -s $SERIAL shell '/data/local/tmp/musl/lib/ld-musl-aarch64.so.1 --library-path /data/local/tmp/musl/usr/lib /data/local/tmp/e2fsck -V 2>&1 | head -1'
" || { echo "PUSH_FAILED" >&2; exit 4; }

# --- 3. run --------------------------------------------------------------
[ "$MODE" = "repair" ] && {
  echo "=== MOUNT GUARD ==="
  mnt="$(ssh -o ConnectTimeout=15 "$HOST" "adb -s $SERIAL shell 'mount | grep -c $DEV' | tr -d '\r'")"
  [ "${mnt:-0}" = "0" ] || { echo "REFUSED: $DEV is mounted; unmount it first" >&2; exit 5; }
  echo "not mounted, ok"
}

echo "=== FSCK ($MODE) on $DEV ==="
RUN="/data/local/tmp/musl/lib/ld-musl-aarch64.so.1 --library-path /data/local/tmp/musl/usr/lib /data/local/tmp/e2fsck"
if [ "$MODE" = "check" ]; then
  ssh -o ConnectTimeout=15 "$HOST" "adb -s $SERIAL shell '$RUN -fn $DEV; echo E2FSCK_RC=\$?'" \
    || { echo "FSCK_CHECK_FAILED" >&2; exit 4; }
else
  ssh -o ConnectTimeout=15 "$HOST" "adb -s $SERIAL shell '$RUN -p $DEV; echo PREEN_RC=\$?; $RUN -fy $DEV; echo FULL_RC=\$?'" \
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
