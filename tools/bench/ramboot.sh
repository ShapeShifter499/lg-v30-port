#!/bin/bash
# RAM-boot a joan image from whatever state the phone is in (pmOS, LineageOS, fastboot).
# Never flashes. Usage: ramboot.sh <boot.img>   (runs on nym-nest)
# Lessons: systemd 262 needs --reboot-argument=bootloader (a positional arg is
# silently rejected); a failed or hung fastboot transfer leaves aboot stuck, so
# every send is time-limited, preceded by a getvar, and followed by a reset.
IMG=$1; S=LGUS9986e606d55; export JOAN_PW=$(cat ~/.config/joan-bench-pw); J=/tmp/ember-f08d8c5-unpack/jssh
log() { echo "$(date +%T) $*"; }
if timeout 8 $J true 2>/dev/null; then
  log "pmOS up: rebooting to bootloader"
  timeout 15 $J "echo $JOAN_PW | sudo -S -p '' sh -c 'sync; systemd-run --on-active=2 systemctl reboot --reboot-argument=bootloader' >/dev/null 2>&1" || true
fi
end=$((SECONDS+300))
while [ $SECONDS -lt $end ]; do
  if sudo fastboot devices | grep -q .; then break; fi
  if sudo adb devices | grep -q "$S.device"; then log "adb seen: reboot bootloader"; sudo adb -s $S reboot bootloader; sleep 5; fi
  if timeout 5 $J true 2>/dev/null; then log "pmOS (old image?) up again: reboot bootloader"; timeout 15 $J "echo $JOAN_PW | sudo -S -p '' systemctl reboot --reboot-argument=bootloader" >/dev/null 2>&1; sleep 10; fi
  sleep 2
done
sudo fastboot devices | grep -q . || { log "NO FASTBOOT after 300s"; exit 2; }
ok=0
for t in 1 2 3; do
  sudo fastboot devices | grep -q . || { log "fastboot gone before try $t"; break; }
  sudo timeout 15 fastboot getvar product >/dev/null 2>&1; sleep 1
  log "fastboot boot try $t"; out=$(sudo timeout 90 fastboot boot "$IMG" 2>&1 | tail -1); log "${out:-timeout}"
  if echo "$out" | grep -q "Finished"; then ok=1; break; fi
  # a failed or hung transfer leaves aboot stuck in its download loop: reset fastboot, wait, retry
  sudo timeout 20 fastboot reboot-bootloader >/dev/null 2>&1; sleep 12
  end2=$((SECONDS+60)); while [ $SECONDS -lt $end2 ]; do sudo fastboot devices | grep -q . && break; sleep 1; done
done
[ $ok = 1 ] || { log "fastboot boot FAILED after retries"; exit 3; }
end=$((SECONDS+200))
while [ $SECONDS -lt $end ]; do
  IF=$(ip -br link | awk '/^enp0s29u1u5/ {print $1}' | head -1)
  if [ -n "$IF" ]; then sudo ip link set $IF up 2>/dev/null; ip -4 addr show $IF | grep -q 172.16.42.2 || sudo ip addr add 172.16.42.2/24 dev $IF 2>/dev/null; fi
  ping -c1 -W1 172.16.42.1 >/dev/null 2>&1 && break
done
log "net: $(ping -c1 -W1 172.16.42.1 >/dev/null 2>&1 && echo up || echo DOWN)"
end=$((SECONDS+240)); until [ $SECONDS -ge $end ] || timeout 10 $J "systemctl is-system-running 2>/dev/null | grep -qE 'running|degraded'" 2>/dev/null; do sleep 5; done
timeout 20 $J 'uname -v; systemctl is-system-running; systemctl --failed --no-legend' 2>&1
