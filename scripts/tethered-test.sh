#!/usr/bin/env bash
# LG V30 (joan) mainline tethered RAM-boot test runner.
#
# Safety contract (binding, see docs/ember-handoff-2026-07-07-*.md):
#   - RAM-only `fastboot boot`, never flash.
#   - Enter fastboot via `adb reboot bootloader` (menu-entered fastboot
#     has wedged aboot before).
#   - Exactly one fastboot client. Two clients can wedge LG aboot.
#   - Never `fastboot getvar` — has wedged aboot before.
#   - Lance must be physically present for device work.
#
# Usage: scripts/tethered-test.sh <boot.img> [timeout_seconds]
#   timeout_seconds: how long to wait for a LineageOS return before
#   giving up (default 300). The classifier ramdisk
#   (out/initramfs-k023b.cpio.gz) reboots on its own at ~90s if it
#   survives, so this should always be well over 90.
#
# Classification on exit:
#   0  — LOS returned early (< 90s after handoff): reset persists.
#        PON/bootreason are read and printed.
#   0  — LOS returned in the 90-200s window: SURVIVOR. Treat as a
#        strong positive signal.
#   10 — no fastboot device appeared within 60s of `adb reboot
#        bootloader`. Nothing was sent to the device; safe to just
#        retry once conditions are checked.
#   11 — `fastboot boot` itself did not report a clean OKAY. Do not
#        retry automatically — record and stop per the safety
#        contract (one attempt per invocation).
#   12 — timeout elapsed with NO LineageOS return, but the device
#        still shows a KNOWN state (plain fastboot, or the normal ADB
#        vendor id 18d1 not yet authorized) — likely just slow, may be
#        safe to keep watching passively (not to retry the boot).
#   13 — timeout elapsed and the device is in an UNFAMILIAR state
#        (lsusb shows something other than the normal ADB identity,
#        e.g. an LG vendor-id 1004:xxxx mode). This happened once
#        (K035, 2026-07-07) after 9 consecutive abnormal resets in a
#        row and needed Lance's physical attention (a plain forced
#        restart, Power+VolDown ~8s) to clear — NOT a flash/KDZ
#        situation. STOP. Do not send further commands.
#   14 — timeout elapsed and the device is completely absent from USB
#        (cable unplugged / phone off). Nothing to do until it's
#        physically reconnected.
set -u

IMG="${1:?usage: tethered-test.sh <boot.img> [timeout_seconds]}"
TIMEOUT="${2:-300}"
[ -f "$IMG" ] || { echo "image not found: $IMG" >&2; exit 2; }

HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
STAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
LOG="$HERE/out/tethered-test-$STAMP.log"
T0=$(date +%s)
ts() { echo "[t+$(( $(date +%s) - T0 ))s] $*" | tee -a "$LOG"; }

usb_line() { lsusb | grep -Ei '18d1|1004|05c6|lg|google|qualcomm' 2>/dev/null; }

: > "$LOG"
ts "image: $IMG (sha256 $(sha256sum "$IMG" | cut -d' ' -f1))"
ts "timeout: ${TIMEOUT}s"

if pgrep -x fastboot >/dev/null 2>&1; then
    ts "FAIL: a fastboot client is already running — refusing to start a second one. Investigate and kill it first."
    exit 10
fi

ts "adb reboot bootloader"
adb reboot bootloader >>"$LOG" 2>&1

FBDEV=""
for i in $(seq 1 30); do
    sleep 2
    OUT=$(sudo -n fastboot devices 2>&1)
    if [ -n "$OUT" ]; then FBDEV="$OUT"; break; fi
done
if [ -z "$FBDEV" ]; then
    ts "FAIL: no fastboot device within 60s of reboot bootloader — nothing sent, safe to re-check and retry"
    exit 10
fi
ts "fastboot sees: $FBDEV"

ts "sudo -n fastboot boot (90s cap on the fastboot command itself)"
timeout 90 sudo -n fastboot boot "$IMG" >>"$LOG" 2>&1
RC=$?
ts "fastboot boot exit code: $RC"
if [ $RC -ne 0 ]; then
    ts "FAIL: no clean OKAY from fastboot boot — stopping per safety contract, not retrying automatically"
    exit 11
fi
TBOOT=$(( $(date +%s) - T0 ))
ts "kernel handed off at t+${TBOOT}s; monitoring for LOS return (cap ${TIMEOUT}s)"

TRET=""
while [ $(( $(date +%s) - T0 )) -lt "$TIMEOUT" ]; do
    sleep 2
    ST=$(adb get-state 2>/dev/null || true)
    if [ "$ST" = "device" ]; then TRET=$(( $(date +%s) - T0 )); break; fi
done

if [ -z "$TRET" ]; then
    FB=$(sudo -n fastboot devices 2>&1)
    USB=$(usb_line)
    if [ -n "$FB" ]; then
        ts "TIMEOUT: still sitting in fastboot ($FB) — likely just slow, safe to keep watching passively"
        exit 12
    elif echo "$USB" | grep -qi '18d1'; then
        ts "TIMEOUT: normal ADB vendor id present but not yet authorized/ready ($USB) — likely just slow"
        exit 12
    elif [ -n "$USB" ]; then
        ts "STOP: device present but in an UNFAMILIAR USB state ($USB) — do not send further commands, needs physical attention"
        exit 13
    else
        ts "STOP: device completely absent from USB — nothing to do until physically reconnected"
        exit 14
    fi
fi

REL=$(( TRET - TBOOT ))
ts "LOS adb returned at t+${TRET}s (${REL}s after handoff)"
if [ $REL -lt 90 ]; then
    ts "CLASSIFICATION: RESET PERSISTS (early LOS return)"
else
    ts "CLASSIFICATION: SURVIVOR window (>=90s = deliberate classifier reboot)"
fi

ts "adb root + PON/bootreason readback"
adb root >>"$LOG" 2>&1
sleep 3
adb wait-for-device >>"$LOG" 2>&1
adb shell 'dmesg | grep -iE "Power-off reason|Power-on reason|PON=0x|LGE BOOT REASON|bootreasoncode" | tail -20' >>"$LOG" 2>&1
adb shell 'getprop ro.boot.bootreason; getprop androidboot.product.lge.bootreasoncode' >>"$LOG" 2>&1
adb unroot >>"$LOG" 2>&1
ts "done — full log: $LOG"
exit 0
