#!/bin/sh
# try to decode RDS on 90.3 MHz over the bench-only fm_cmd hook
F=/sys/kernel/debug/bluetooth/hci0/fm_cmd
echo "fmrds start" > /dev/kmsg
echo "16 4c 01 07" > $F; sleep 0.2                                    # event mask: signal, RDS sync, audio
echo "04 4c 0c 00 00 00 00 cc 55 01 00 e0 a5 01 00" > $F; sleep 0.2   # 75us, 200k, RBDS, 87.5-108
echo "12 4c 0c ff ff ff ff 01 00 00 00 00 00 00 00" > $F; sleep 0.2   # all RDS groups, buffer 1
echo "13 4c 04 ff 00 00 00" > $F; sleep 0.2                           # all RDS processing
echo "01 54 04 bc 60 01 00" > $F; sleep 1                             # tune 90300 kHz
i=0
while [ $i -lt 10 ]; do
	echo "0b 4c 00" > $F; sleep 1        # program service (station name)
	echo "0c 4c 00" > $F; sleep 1        # radio text
	i=$((i + 1))
done
echo "fmrds end" > /dev/kmsg
