#!/bin/sh
# capture RDS events on a strong station (run as root)
F=${1:-103.5}; T=${2:-25}
install -m644 /tmp/radio-qca-fm-rds.ko.zst /lib/modules/$(uname -r)/kernel/drivers/media/radio/radio-qca-fm.ko.zst
rmmod radio_qca_fm; modprobe radio_qca_fm; sleep 1
echo "module radio_qca_fm +p" > /sys/kernel/debug/dynamic_debug/control
echo "rdscap $F" > /dev/kmsg
( exec 3</dev/radio0; v4l2-ctl -d /dev/radio0 -f $F >/dev/null; v4l2-ctl -d /dev/radio0 -T | grep -E 'Signal|Avail'; sleep $T )
dmesg | sed -n "/rdscap $F/,\$p" | grep -oE 'event 0x[0-9a-f]+: .*' > /tmp/rdscap.txt
awk '{print $2}' /tmp/rdscap.txt | sort | uniq -c
