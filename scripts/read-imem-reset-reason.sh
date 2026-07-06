#!/usr/bin/env bash
# Read LG V30 (joan) IMEM reset-reason cookies from the RUNNING LineageOS
# (downstream 4.4) over adb. Read-only: no writes, no flash. Run this AFTER
# a mainline oracle boot round has crash-reset back into LineageOS.
#
# Pairs with the joan/imem-oracle kernel branch (out/boot-joan-imem-oracle.img).
# Needs: adb, and root on the phone (LOS "Rooted debugging" / su).
#
# IMEM layout (from downstream lge_handle_panic + msm8998.dtsi imem node):
#   0x146bf65c  restart_reason  — reset CAUSE the boot chain recorded
#   0x146bf640  scratch         — 0x4a4f414e "JOAN" if our initcall ran
#   0x146bf04c  crash_magic     — 0x4c474500 if boot-chain cookie present
set -u

ADB="${ADB:-adb}"
run() { sudo -n $ADB shell "su -c '$*'" 2>/dev/null || sudo -n $ADB shell "$*" 2>/dev/null; }

echo "== device =="
sudo -n $ADB devices | sed -n '2p'

echo "== IMEM cookies (need root) =="
for pair in "restart_reason:0x146bf65c" "sentinel_JOAN:0x146bf640" "crash_magic:0x146bf04c"; do
    name=${pair%%:*}; addr=${pair##*:}
    val=$(run "busybox devmem $addr 32" || run "devmem $addr 32")
    printf "  %-16s %s = %s\n" "$name" "$addr" "${val:-<no read / no root>}"
done

echo "== decode restart_reason =="
cat <<'TABLE'
  0x6d630300  LGE_ERR_TZ (generic TZ / our written default)
  0x6d63033a  TZ non-secure watchdog BARK   <-- watchdog culprit
  0x6d63033b  TZ thermal secure BITE        <-- thermal culprit
  0x6d630301  kernel
  0x6d630201  RPM
  0x6d630400  hyp
  0x6d630500  LAF
  (0x6d63xxxx with LGE_SUB_* nibble = subsystem crash; see lge_handle_panic.h)
  If reason == 0x6d630300 exactly, either nothing overwrote our default
  (reset came from a path that does NOT record an LGE reason -> suspect a
  raw PMIC/PON or PS_HOLD reset), or the reset beat our initcall.
  If sentinel != 0x4a4f414e, our early_initcall did NOT run before reset
  -> reset is earlier than early_initcall; move the probe earlier.
TABLE

echo "== also useful: last bootreason from LG props / cmdline =="
run "getprop | grep -iE 'boot.*reason|lge.*boot'"
run "cat /proc/cmdline" | tr ' ' '\n' | grep -iE 'reason|reboot|warmboot' || true
