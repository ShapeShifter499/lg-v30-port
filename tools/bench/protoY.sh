#!/bin/sh
# arm with 20 spaced sessions (default autosuspend), then set delays and run 20 back-to-back
IMX=$1; CCI=$2
: > /home/user/camrace.log; : > /home/user/camvf.log
echo "$(date +%T) protoY imx=$IMX cci=$CCI arming" >> /home/user/camrace.log; sync
sh /home/user/camvfstress.sh 20
echo $IMX > /sys/bus/i2c/devices/5-0010/power/autosuspend_delay_ms
echo $CCI > /sys/devices/platform/soc@0/ca0c000.cci/power/autosuspend_delay_ms
echo "$(date +%T) armed; delays imx=$(cat /sys/bus/i2c/devices/5-0010/power/autosuspend_delay_ms) cci=$(cat /sys/devices/platform/soc@0/ca0c000.cci/power/autosuspend_delay_ms)" >> /home/user/camrace.log; sync
sh /home/user/camrace.sh 20 0
echo "$(date +%T) ALLDONE" >> /home/user/camrace.log; sync
