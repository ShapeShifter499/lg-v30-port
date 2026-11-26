#!/bin/sh
# FM receive sweep over the bench-only hci_qca fm_cmd hook
F=/sys/kernel/debug/bluetooth/hci0/fm_cmd
[ -e $F ] || { echo "no fm_cmd"; exit 1; }
bluetoothctl power on >/dev/null 2>&1; sleep 1
hex() { printf '%02x %02x %02x %02x' $(( $1 & 255 )) $(( ($1 >> 8) & 255 )) $(( ($1 >> 16) & 255 )) $(( ($1 >> 24) & 255 )); }
echo "fmscan start" > /dev/kmsg
echo "01 4c 00" > $F; sleep 0.3                                   # recv enable
echo "04 4c 0c 00 00 00 00 cc 55 01 00 e0 a5 01 00" > $F; sleep 0.2  # 75us, 200k, RBDS, 87.5-108
k=87900
while [ $k -le 107900 ]; do
	echo "fmscan tune $k" > /dev/kmsg
	echo "01 54 04 $(hex $k)" > $F; sleep 0.12
	echo "0a 54 00" > $F; sleep 0.08
	k=$((k + 200))
done
echo "fmscan end" > /dev/kmsg
