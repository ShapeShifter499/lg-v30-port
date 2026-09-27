#!/bin/sh
# read-only: which focus controller does this IMX351 module carry? (run as root)
modprobe i2c-dev 2>/dev/null
command -v i2ctransfer >/dev/null || { echo "no i2c-tools"; exit 1; }
for b in /sys/bus/i2c/devices/i2c-*; do echo "${b##*/}: $(cat $b/name)"; done | grep -i cci
BUS=$(for b in /sys/bus/i2c/devices/i2c-*; do grep -qi cci $b/name && echo ${b##*-}; done | head -1)
echo "probing bus $BUS while the sensor streams"
timeout 20 cam -c1 --capture=200 -s width=1280,height=720 >/dev/null 2>&1 &
sleep 3
echo "eeprom map_ver @0xbe2: $(i2ctransfer -y $BUS w2@0x54 0x0b 0xe2 r1 2>&1)"
echo "eeprom cal_ver @0xac2: $(i2ctransfer -y $BUS w2@0x54 0x0a 0xc2 r2 2>&1)"
echo "eeprom head @0x000:    $(i2ctransfer -y $BUS w2@0x54 0x00 0x00 r16 2>&1)"
echo "rohm 0x3e status 0x6024: $(i2ctransfer -y $BUS w2@0x3e 0x60 0x24 r1 2>&1)"
echo "renesas 0x24 status 0x0001: $(i2ctransfer -y $BUS w2@0x24 0x00 0x01 r1 2>&1)"
wait
