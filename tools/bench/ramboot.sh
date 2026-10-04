#!/bin/bash
# RAM-boot a joan image. NEVER flashes.
# Usage: ramboot.sh <boot.img>   (runs on nym-nest)
#
# THE CRITICAL TIMING (Lance, 2026-10-04): aboot's download session times out.
# The host must ALREADY be running `fastboot boot <img>` (parked at "waiting for
# device") when the phone enters fastboot mode, so the transfer fires the instant
# the device enumerates. Firing the send after enumeration loses the race and the
# session stalls (the 2026-10-03 "no RAM boot" outage). So: ARM FIRST, then
# trigger the reboot into the bootloader.
#
# A failed/hung session: do NOT reboot-bootloader or reset — that drives LG aboot
# into its "any key to shutdown" error screen. Getvar probes before the send can
# desync aboot; the armed-send pattern needs none.
IMG=$1; S=LGUS9986e606d55; export JOAN_PW=$(cat ~/.config/joan-bench-pw); J=/tmp/ember-f08d8c5-unpack/jssh
log() { echo "$(date +%T) $*"; }
[ -f "$IMG" ] || { log "no image: $IMG"; exit 1; }
[ -f "$IMG.done" ] || { log "REFUSING: $IMG.done missing — verify the pull completed (a truncated image boots as BootImage Incomplete)"; exit 1; }

# 1. ARM the send: fastboot boot parks on "waiting for device".
sudo fastboot devices | grep -q . && { log "phone already in fastboot; sending directly"; sudo timeout 90 fastboot boot "$IMG" 2>&1 | sed 's/^/    /'; exit 0; }
sudo nohup timeout 120 fastboot boot "$IMG" > /tmp/fb-armed.log 2>&1 &
ARMED=$!
log "armed: fastboot boot waiting for device (pid $ARMED)"

# 2. Trigger the reboot into the bootloader.
triggered=0
if timeout 8 $J true 2>/dev/null; then
  log "pmOS up: rebooting to bootloader"
  timeout 15 $J "echo $JOAN_PW | sudo -S -p '' sh -c 'sync; systemctl reboot --reboot-argument=bootloader' >/dev/null 2>&1" || true
  triggered=1
elif sudo adb devices | grep -q "$S.device"; then
  log "adb: reboot bootloader"
  sudo adb -s $S reboot bootloader
  triggered=1
fi
[ $triggered = 1 ] || { log "no pmOS/adb path to reboot; kill the armed send"; sudo kill $ARMED 2>/dev/null; exit 2; }

# 3. Wait for the armed send to complete (it fires on enumeration).
end=$((SECONDS+120)); ok=0
while [ $SECONDS -lt $end ]; do
  if grep -q "Finished" /tmp/fb-armed.log 2>/dev/null && ! grep -qi "fail" /tmp/fb-armed.log 2>/dev/null; then ok=1; break; fi
  grep -qi "error\|FAILED" /tmp/fb-armed.log 2>/dev/null && break
  sleep 2
done
sed 's/^/    /' /tmp/fb-armed.log
[ $ok = 1 ] || { log "armed send failed; phone left as-is (no reset)"; exit 3; }
log "sent; waiting for pmOS"

# 4. Net + sshd wait (unchanged).
end=$((SECONDS+200))
while [ $SECONDS -lt $end ]; do
  IF=$(ip -br link | awk '/^enp0s29u1u[0-9]/ {print $1}' | head -1)
  if [ -n "$IF" ]; then sudo ip link set $IF up 2>/dev/null; ip -4 addr show $IF | grep -q 172.16.42.2 || sudo ip addr add 172.16.42.2/24 dev $IF 2>/dev/null; fi
  ping -c1 -W1 172.16.42.1 >/dev/null 2>&1 && break
done
log "net: $(ping -c1 -W1 172.16.42.1 >/dev/null 2>&1 && echo up || echo DOWN)"
end=$((SECONDS+240)); until [ $SECONDS -ge $end ] || timeout 10 $J "systemctl is-system-running 2>/dev/null | grep -qE 'running|degraded'" 2>/dev/null; do sleep 5; done
timeout 20 $J 'uname -v; systemctl is-system-running; systemctl --failed --no-legend' 2>&1
