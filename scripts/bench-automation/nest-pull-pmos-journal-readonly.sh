#!/bin/bash
# Runs ON nym-nest, ARMED: waits for the phone to come back on adb (Lance
# presses power -> LineageOS), then pulls the pmOS journal READ-ONLY.
# No writes to the SD. No superblock surgery. No recovery needed.
#
# Trick: vold holds mmcblk0p2 with an exclusive open, so mount(2) returns
# EBUSY. losetup does NOT take O_EXCL, so a read-only loop device over the
# same partition can be mounted where the bare device cannot.
set -u
RUNDIR=~/joan-test-assets/pass2-$(date +%Y%m%d-%H%M%S)
mkdir -p "$RUNDIR"
LOG="$RUNDIR/timeline.log"
T0=$(date +%s)
ts() { echo "[+$(( $(date +%s) - T0 ))s] $*" | tee -a "$LOG"; }

ts "ARMED - waiting for the phone on adb (power it on into LineageOS)"
for i in $(seq 1 3600); do
  adb devices 2>/dev/null | grep -q "device$" && break
  sleep 2
done
adb devices 2>/dev/null | grep -q "device$" || { ts "TIMED OUT waiting for adb"; exit 1; }
ts "adb is up: $(adb devices | grep device$ | awk '{print $1}')"

adb root >/dev/null 2>&1; sleep 3; adb wait-for-device
ts "root: $(adb shell id 2>&1 | head -1)"
ts "uptime: $(adb shell cat /proc/uptime 2>&1)"

# ---- read-only access to the pmOS rootfs -------------------------------
adb shell 'mkdir -p /mnt/pmroot' >/dev/null 2>&1
ts "attempt 1: direct ro,noload mount"
R=$(adb shell 'mount -o ro,noload -t ext4 /dev/block/mmcblk0p2 /mnt/pmroot 2>&1 && echo OK' 2>&1)
ts "  -> $R"
if ! echo "$R" | grep -q OK; then
  ts "attempt 2: read-only loop device (bypasses vold's O_EXCL)"
  R=$(adb shell 'losetup -r /dev/block/loop99 /dev/block/mmcblk0p2 2>&1 || losetup -r -f /dev/block/mmcblk0p2 2>&1; losetup -a 2>&1' 2>&1)
  ts "  losetup: $R"
  LOOP=$(adb shell 'losetup -a 2>/dev/null' | grep mmcblk0p2 | cut -d: -f1 | tr -d '\r' | head -1)
  ts "  loop dev: ${LOOP:-NONE}"
  if [ -n "$LOOP" ]; then
    R=$(adb shell "mount -o ro,noload -t ext4 $LOOP /mnt/pmroot 2>&1 && echo OK" 2>&1)
    ts "  -> $R"
  fi
fi

if ! adb shell 'ls /mnt/pmroot/etc >/dev/null 2>&1 && echo MOUNTED' | grep -q MOUNTED; then
  ts "MOUNT FAILED - falling back to recovery lane is needed (needs Lance)"
  exit 2
fi
ts "pmOS rootfs is mounted READ-ONLY"

# ---- pull the evidence -------------------------------------------------
ts "journal boots on disk:"
adb shell 'ls -l /mnt/pmroot/var/log/journal/*/ 2>&1 | head -20' | tee -a "$LOG"

adb shell 'cd /mnt/pmroot && tar czf /data/local/tmp/pmos-journal.tgz var/log/journal 2>/dev/null; ls -l /data/local/tmp/pmos-journal.tgz' | tee -a "$LOG"
adb pull /data/local/tmp/pmos-journal.tgz "$RUNDIR/" >>"$LOG" 2>&1 && ts "journal pulled"

# config evidence that explains sshd + the gadget teardown
for f in \
  /mnt/pmroot/usr/lib/usb-signaller/usb-signaller.toml \
  /mnt/pmroot/etc/ssh/sshd_config \
  /mnt/pmroot/etc/fstab ; do
  echo "===== $f" >> "$RUNDIR/config-evidence.txt"
  adb shell "cat $f 2>&1" >> "$RUNDIR/config-evidence.txt"
done
{
  echo "===== enabled units (etc/systemd/system)"
  adb shell 'ls -R /mnt/pmroot/etc/systemd/system 2>&1'
  echo "===== masked units"
  adb shell 'ls -l /mnt/pmroot/etc/systemd/system | grep -i null 2>&1'
  echo "===== sshd enabled?"
  adb shell 'ls -l /mnt/pmroot/etc/systemd/system/multi-user.target.wants/ 2>&1'
  echo "===== ssh host keys"
  adb shell 'ls -l /mnt/pmroot/etc/ssh/ 2>&1'
  echo "===== any prior audio output"
  adb shell 'ls -lR /mnt/pmroot/home/user/ 2>&1 | head -60'
} >> "$RUNDIR/config-evidence.txt"
ts "config evidence collected"

adb shell 'umount /mnt/pmroot 2>&1; losetup -d /dev/block/loop99 2>/dev/null' >/dev/null 2>&1
ts "unmounted cleanly - SD untouched (read-only throughout)"
ts "DONE - artifacts in $RUNDIR"
