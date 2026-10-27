#!/bin/sh
# vl53l0x runtime PM: idle -> read -> idle -> unbind/rebind, rails at each step
P=/sys/bus/i2c/devices/5-0029
rails() { printf '%-10s rpm=%-9s ' "$1" "$(cat $P/power/runtime_status 2>/dev/null)"; grep -E '^ *(lvs1|cam0_avdd_2p8) ' /sys/kernel/debug/regulator/regulator_summary | awk '{printf "%s use=%s  ", $1, $2}'; echo; }
dev() { for d in /sys/bus/iio/devices/iio:device*; do [ "$(cat $d/name)" = vl53l0x ] && echo $d; done; }
n0=$(dmesg | wc -l)
rails idle
D=$(dev); echo "iio=$D"
t0=$(date +%s%N); v=$(cat $D/in_distance_raw); t1=$(date +%s%N); echo "read=$v in $(( (t1-t0)/1000000 )) ms"
rails after-read
sleep 2; rails +2s
for i in 1 2 3 4 5; do cat $D/in_distance_raw; done | tr '\n' ' '; echo "(5 reads)"
sleep 2; rails +2s
echo 5-0029 > /sys/bus/i2c/drivers/vl53l0x-i2c/unbind; rails unbound
echo 5-0029 > /sys/bus/i2c/drivers/vl53l0x-i2c/bind; echo "bind rc=$?"; sleep 2; rails rebound+2s
D=$(dev); cat $D/in_distance_raw
modprobe -r vl53l0x_i2c; rails rmmod
modprobe vl53l0x_i2c; sleep 2; rails modprobe+2s
dmesg | tail -n +$((n0+1)) | grep -iE 'vl53|cci|regulator|unbalanced|WARNING|Call trace' | head
