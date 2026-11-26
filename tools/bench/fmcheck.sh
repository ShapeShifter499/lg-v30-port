#!/bin/sh
# repeat the sweep, then dwell on 90.3 MHz with each antenna setting
F=/sys/kernel/debug/bluetooth/hci0/fm_cmd
hex() { printf '%02x %02x %02x %02x' $(( $1 & 255 )) $(( ($1 >> 8) & 255 )) $(( ($1 >> 16) & 255 )) $(( ($1 >> 24) & 255 )); }
echo "fmcheck start" > /dev/kmsg
k=87900
while [ $k -le 107900 ]; do echo "fmscan tune $k" > /dev/kmsg; echo "01 54 04 $(hex $k)" > $F; sleep 0.12; k=$((k + 200)); done
for ant in 0 1; do
	echo "fmcheck antenna $ant" > /dev/kmsg; echo "07 4c 01 0$ant" > $F; sleep 0.2
	for i in 1 2 3; do echo "fmscan tune 90300" > /dev/kmsg; echo "01 54 04 $(hex 90300)" > $F; sleep 0.3; done
done
echo "fmcheck end" > /dev/kmsg
