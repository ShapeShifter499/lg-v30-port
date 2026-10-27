#!/bin/sh
# A/B: does the VL53L0X answer on CCI only while the IMX351's rails are up?
C=/sys/bus/i2c/devices/5-0010/power
D=/sys/bus/i2c/drivers/vl53l0x-i2c
try() {
	echo "--- $1: imx351 control=$(cat $C/control) status=$(cat $C/runtime_status)"
	grep -E 'lvs1|cam0|avdd|dvdd' /sys/kernel/debug/regulator/regulator_summary | awk '{print $1,$2,$3,$4}' | head -6
	n=$(dmesg | wc -l)
	echo 5-0029 > $D/bind 2>/dev/null; echo "bind rc=$?"
	sleep 1
	dmesg | tail -n +$((n+1)) | grep -iE 'vl53|cci' | sed 's/^\[[^]]*\] //'
	[ -e /sys/bus/i2c/devices/5-0029/driver ] && { echo BOUND; ls /sys/bus/i2c/devices/5-0029/ | grep -c iio; echo 5-0029 > $D/unbind; }
}
echo auto > $C/control; sleep 3; try A1
echo on > $C/control; sleep 1; try B
echo auto > $C/control; sleep 3; try A2
