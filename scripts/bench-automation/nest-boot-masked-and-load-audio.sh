#!/bin/bash
set -u
IP=172.16.42.1; PW="${JOAN_PW:?set JOAN_PW to the bench password}"
IMG=~/joan-test-assets/audio-wake-20260907/boot-joan-pmos-audio-wake-20260907-v2-label.img
CMD="panic=5 pmos.force-partition-resize pmos_rootfsopts=defaults systemd.mask=usb-signaller.service"
RUNDIR=~/joan-test-assets/pass5-$(date +%Y%m%d-%H%M%S); mkdir -p "$RUNDIR"
LOG="$RUNDIR/timeline.log"; T0=$(date +%s)
SO="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR"
ts(){ echo "[+$(( $(date +%s) - T0 ))s] $*" | tee -a "$LOG"; }
sshp(){ sshpass -p "$PW" ssh $SO "user@$IP" "$@"; }

ts "reboot to bootloader"; adb reboot bootloader >>"$LOG" 2>&1
for i in $(seq 1 60); do sudo -n fastboot devices 2>/dev/null | grep -q . && break; sleep 1; done
ts "fastboot: $(sudo -n fastboot devices 2>&1 | tr '\n' ' ')"
sudo -n fastboot boot "$IMG" --cmdline "$CMD" >>"$LOG" 2>&1
ts "booted"

IFACE=""
for i in $(seq 1 400); do
  for d in /sys/class/net/*; do [ -e "$d/device/driver" ] || continue
    case "$(readlink -f "$d/device/driver")" in *cdc_ncm*) IFACE=$(basename "$d");; esac; done
  [ -n "$IFACE" ] && break; sleep 0.25
done
ts "netdev $IFACE"
sudo -n ip addr flush dev "$IFACE" 2>/dev/null
sudo -n ip link set "$IFACE" up; sudo -n ip addr add 172.16.42.2/24 dev "$IFACE"
for i in $(seq 1 600); do timeout 1 bash -c "echo >/dev/tcp/$IP/22" 2>/dev/null && break; sleep 0.5; done
ts "sshd up"

sshpass -p "$PW" scp $SO ~/joan-test-assets/joan-modules.tgz ~/joan-test-assets/onphone-pass5.sh ~/joan-test-assets/onphone-pass4b.sh "user@$IP:/tmp/" >>"$LOG" 2>&1
ts "pushed"

# live evidence channels - survive a SoC reset because they land on the nest
( printf '%s\n' "$PW" | sshpass -p "$PW" ssh $SO "user@$IP" 'sudo -S dmesg -w' > "$RUNDIR/dmesg-live.txt" 2>&1 ) &
DPID=$!
( sshpass -p "$PW" ssh $SO "user@$IP" 'while :; do echo "HB $(cut -d" " -f1 /proc/uptime)"; sleep 1; done' > "$RUNDIR/heartbeat.txt" 2>&1 ) &
HPID=$!
sleep 3
ts "evidence channels open (dmesg $(wc -l <"$RUNDIR/dmesg-live.txt") lines, hb $(wc -l <"$RUNDIR/heartbeat.txt"))"

ts "running staged module load"
printf '%s\n' "$PW" | sshpass -p "$PW" ssh $SO "user@$IP" 'sudo -S sh /tmp/onphone-pass5.sh' 2>&1 | tee "$RUNDIR/steps.log"
ts "staged load returned"

if grep -q "^@@.*CARDS:" "$RUNDIR/steps.log" && sshp 'test -e /proc/asound/cards' 2>/dev/null; then
  ts "*** SOUND CARD EXISTS - running capture ***"
  printf '%s\n' "$PW" | sshpass -p "$PW" ssh $SO "user@$IP" 'sudo -S sh /tmp/onphone-pass4b.sh' >>"$LOG" 2>&1
  sshpass -p "$PW" scp -r $SO "user@$IP:/tmp/joan-pass4" "$RUNDIR/" >>"$LOG" 2>&1 && ts "capture pulled"
else
  ts "no sound card - skipping capture"
fi
kill $DPID $HPID 2>/dev/null
ts "last heartbeat: $(tail -1 "$RUNDIR/heartbeat.txt" 2>/dev/null)"
ts "DONE -> $RUNDIR"
