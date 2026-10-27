#!/bin/bash
# nest side: wait for the handset to come back in LineageOS, then RAM-boot IMG
IMG=${IMG:-$HOME/joan-images/boot-joan-bl17.img}
cd /tmp/ember-f08d8c5-unpack
end=$((SECONDS+2400))
while [ $SECONDS -lt $end ]; do sudo adb devices | grep -q "LGUS9986e606d55.device" && break; sudo fastboot devices | grep -q . && break; sleep 3; done
if sudo adb devices | grep -q "LGUS9986e606d55.device"; then
	echo "$(date +%T) adb up, rebooting to bootloader"
	sudo adb -s LGUS9986e606d55 reboot bootloader
	e=$((SECONDS+60)); while [ $SECONDS -lt $e ]; do sudo fastboot devices | grep -q . && break; sleep 1; done
fi
sudo fastboot devices | grep -q . || { echo "no fastboot device"; exit 1; }
echo "$(date +%T) fastboot boot $IMG"; sudo fastboot boot $IMG 2>&1 | tail -1
e=$((SECONDS+200)); while [ $SECONDS -lt $e ]; do IF=$(ip -br link | awk '/^enp0s29u1u5/ {print $1}' | head -1); if [ -n "$IF" ]; then sudo ip link set $IF up 2>/dev/null; ip -4 addr show $IF | grep -q 172.16.42.2 || sudo ip addr add 172.16.42.2/24 dev $IF 2>/dev/null; fi; ping -c1 -W1 172.16.42.1 >/dev/null 2>&1 && break; done
e=$((SECONDS+240)); until [ $SECONDS -ge $e ] || timeout 8 ./jssh "echo alive" 2>/dev/null | grep -q alive; do sleep 5; done
timeout 8 ./jssh "uname -r; cat /proc/cmdline" 2>&1 | tail -2
echo "$(date +%T) done"
