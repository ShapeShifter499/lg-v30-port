#!/bin/sh
modprobe netconsole netconsole=6665@172.16.42.1/usb0,6666@172.16.42.2/8e:87:70:f0:79:ba || exit 1
echo "bc: netconsole armed" > /dev/kmsg
grep -A2 -E "usb@a8f8800|a8f8800" /sys/kernel/debug/interconnect/interconnect_summary | head -6
