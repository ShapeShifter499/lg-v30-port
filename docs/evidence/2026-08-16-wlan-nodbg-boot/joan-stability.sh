#!/bin/sh
# Long-window modem-stability check on the SAME boot that brought wlan0 up.
#
# The Aug-14 baseline crashed the modem every 20-28s inside wlan_process, and
# Aurel root-caused the fatal error to scanning channel 169 / 5845 MHz.
# 519646f01 withholds 5845 MHz. This repeats 5 GHz scans over a long window and
# watches for the crash signature, so the claim rests on more than one 160s boot.
set -u
IW=$(find /tmp/iwtool -name iw -type f 2>/dev/null | head -1)
[ -n "$IW" ] || { echo "IW_MISSING (tmpfs wiped? re-stage)"; exit 1; }

echo "uptime_start=$(cut -d. -f1 /proc/uptime)s"
echo "kernel=$(uname -r)"
echo "mss=$(cat /sys/class/remoteproc/remoteproc0/state 2>/dev/null)"
echo "wlan0_present=$(ls /sys/class/net | grep -c '^wlan0$')"
echo "fatal_at_start=$(dmesg | grep -ic 'fatal error')"
echo "recover_at_start=$(dmesg | grep -ic 'successfully recovered')"

i=1
while [ $i -le 6 ]; do
    echo "--- scan $i (t=$(cut -d. -f1 /proc/uptime)s) ---"
    "$IW" dev wlan0 scan passive > /tmp/s.txt 2>/dev/null || "$IW" dev wlan0 scan > /tmp/s.txt 2>/dev/null
    echo "bss=$(grep -c '^BSS ' /tmp/s.txt 2>/dev/null)"
    echo "bss_5ghz=$(grep -oE 'freq: [0-9]+' /tmp/s.txt 2>/dev/null | awk '$2>=5000' | wc -l)"
    echo "max_freq=$(grep -oE 'freq: [0-9]+' /tmp/s.txt 2>/dev/null | awk '{print $2}' | sort -n | tail -1)"
    echo "fatal=$(dmesg | grep -ic 'fatal error')  mss=$(cat /sys/class/remoteproc/remoteproc0/state 2>/dev/null)"
    i=$((i + 1))
    [ $i -le 6 ] && sleep 60
done

echo "=== final ==="
echo "uptime_end=$(cut -d. -f1 /proc/uptime)s"
echo "fatal_total=$(dmesg | grep -ic 'fatal error')"
echo "recover_total=$(dmesg | grep -ic 'successfully recovered')"
echo "mss=$(cat /sys/class/remoteproc/remoteproc0/state 2>/dev/null)"
echo "--- any 5845/channel-169 in scan results (should be NONE) ---"
grep -oE 'freq: 58[0-9]+' /tmp/s.txt 2>/dev/null | sort -u | tail -5
echo "--- crash signature lines, if any ---"
dmesg | grep -iE "fatal error|crash detected|wlan_process" | tail -8
echo "--- ath10k tail ---"
dmesg | grep -i ath10k | tail -6
echo "DONE_STABILITY"
