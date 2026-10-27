#!/bin/sh
# Post-boot verification for the joan bench. Runs ON the phone (as root):
#   jssh scp joan-verify.sh user@172.16.42.1: && jssh "echo \$JOAN_PW | sudo -S sh joan-verify.sh"
# Prints one section per check; every line is a fact, not a verdict, so the
# report can be diffed between kernels.

sec() { printf '\n== %s\n' "$1"; }

sec system
uname -r
cat /proc/cmdline
systemctl is-system-running
systemctl --failed --no-legend
cat /sys/kernel/security/lsm; echo

sec cpu
for p in /sys/devices/system/cpu/cpufreq/policy*; do
	echo "$(basename "$p") $(cat "$p/scaling_driver") gov=$(cat "$p/scaling_governor")" \
	     "max=$(cat "$p/cpuinfo_max_freq")"
done
cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null | sed 's/^/lru_gen=/'

sec gpu
dmesg | grep -E 'GFX open-loop|a540|adreno 5000000' | head -6
for f in /sys/kernel/debug/opp/*5000000*/opp:*; do
	[ -d "$f" ] || continue
	printf '%s %s uV\n' "$(cat "$f/rate_hz")" "$(cat "$f"/supply-0/u_volt_target 2>/dev/null)"
done
d=/sys/class/devfreq/5000000.gpu
echo "devfreq gov=$(cat $d/governor) cur=$(cat $d/cur_freq)"
dmesg | grep -c -E 'gpu fault|hangcheck' | sed 's/^/gpu faults+hangchecks: /'
dmesg | grep -E 'iova=0*1000' | head -2

sec audio
dmesg | grep -E 'soundwire|Flags mismatch irq|swm' | head -4
cat /proc/asound/cards

sec thermal
for z in /sys/class/thermal/thermal_zone*; do
	t=$(cat "$z/type"); case "$t" in cpu4*|gpu-top*|skin*|pm8998*) ;; *) continue ;; esac
	printf '%s %s' "$t" "$(cat "$z/temp")"
	for tp in "$z"/trip_point_*_temp; do printf ' %s' "$(cat "$tp")"; done; echo
done

sec devices
for i in /sys/class/input/input*; do cat "$i/name"; done | grep -i -E 'dw7800|haptic|vibra' || echo "no haptics input"
for d in /sys/bus/iio/devices/iio:device*; do echo "iio $(cat "$d/name")"; done
for c in /sys/bus/i2c/devices/*; do
	n=$(cat "$c/name" 2>/dev/null); case "$n" in imx351|vl53l0x|sx9320|dw7800) ;; *) continue ;; esac
	echo "i2c $n driver=$(basename "$(readlink "$c/driver")" 2>/dev/null)"
done

sec userspace
journalctl -b --no-pager | grep -E 'bpf-restrict-fs|Failed to find module|RFCOMM server failed' | head -5
lsmod | grep -E '^(uhid|uinput|rfcomm|bnep|nxp_nci)' | awk '{print $1}' | tr '\n' ' '; echo

sec bootlog
dmesg --level=emerg,alert,crit,err,warn | wc -l | sed 's/^/kernel err+warn lines: /'
journalctl -b -p warning --no-pager | wc -l | sed 's/^/journal warning+ lines: /'
stat -c 'root dir %U:%G %a' /
