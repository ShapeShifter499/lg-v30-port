#!/bin/sh
# FM receiver through the V4L2 radio driver (run as root)
R=/dev/radio0
bluetoothctl power on >/dev/null 2>&1; sleep 2
[ -e $R ] || { echo "no $R"; ls /sys/bus/auxiliary/devices/; dmesg | grep -iE 'fm|radio' | tail -5; exit 1; }
echo "fmtest start" > /dev/kmsg
v4l2-ctl -d $R -D | head -8
v4l2-ctl -d $R --list-freq-bands
echo "== tune 90.3"; v4l2-ctl -d $R -f 90.3 && v4l2-ctl -d $R -F && v4l2-ctl -d $R -T | grep -E 'Signal|Available|Current|Rx'
echo "== hold open 3 s, tuner twice"; ( exec 3<$R; v4l2-ctl -d $R -f 90.3 >/dev/null; v4l2-ctl -d $R -T | grep -E 'Signal|Rx'; sleep 3; v4l2-ctl -d $R -T | grep -E 'Signal|Rx'; exec 3<&- )
echo "== seek up, wrap"; t=$(date +%s); v4l2-ctl -d $R --freq-seek=dir=1,wrap=1; echo "rc=$? $(( $(date +%s) - t ))s"; v4l2-ctl -d $R -F
echo "== seek up again"; v4l2-ctl -d $R --freq-seek=dir=1,wrap=1; echo "rc=$?"; v4l2-ctl -d $R -F
echo "== seek down, no wrap"; v4l2-ctl -d $R --freq-seek=dir=0,wrap=0; echo "rc=$?"; v4l2-ctl -d $R -F
echo "== mute"; v4l2-ctl -d $R -c mute=1 && v4l2-ctl -d $R -C mute
echo "== bt off"; bluetoothctl power off >/dev/null; sleep 1; v4l2-ctl -d $R -T 2>&1 | tail -1; bluetoothctl power on >/dev/null; sleep 2; v4l2-ctl -d $R -f 90.3 && v4l2-ctl -d $R -F
echo "fmtest end" > /dev/kmsg
dmesg | grep -iE 'radio|fm |hci_uart.fm|FM ' | tail -12
command -v v4l2-compliance >/dev/null && v4l2-compliance -d $R 2>&1 | tail -15
