#!/bin/bash
# nest side: one venus bisect round. Usage: venus-bisect.sh "<modprobe args>"
ARGS="$1"; IMG=${IMG:-$HOME/joan-images/boot-joan-bl16.img}
export JOAN_PW=$(cat ~/.config/joan-bench-pw); cd /tmp/ember-f08d8c5-unpack
up() { timeout 8 ./jssh "echo alive" 2>/dev/null | grep -q alive; }
if ! up; then
	end=$((SECONDS+120)); while [ $SECONDS -lt $end ]; do sudo adb devices | grep -q "LGUS9986e606d55.device" && break; sleep 3; done
	sudo adb -s LGUS9986e606d55 reboot bootloader; end=$((SECONDS+60)); while [ $SECONDS -lt $end ]; do sudo fastboot devices | grep -q . && break; sleep 1; done
	sudo fastboot boot $IMG 2>&1 | tail -1
	end=$((SECONDS+200)); while [ $SECONDS -lt $end ]; do IF=$(ip -br link | awk '/^enp0s29u1u5/ {print $1}' | head -1); if [ -n "$IF" ]; then sudo ip link set $IF up 2>/dev/null; ip -4 addr show $IF | grep -q 172.16.42.2 || sudo ip addr add 172.16.42.2/24 dev $IF 2>/dev/null; fi; ping -c1 -W1 172.16.42.1 >/dev/null 2>&1 && break; done
	end=$((SECONDS+240)); until [ $SECONDS -ge $end ] || ./jssh "systemctl is-system-running 2>/dev/null | grep -qE 'running|degraded'" 2>/dev/null; do sleep 5; done
fi
./jssh "uname -r; lsmod | grep -c '^venus'"
./jssh "echo $JOAN_PW | sudo -S -p '' systemd-run --unit=vb\$RANDOM sh -c 'echo \"venus-bisect: modprobe venus_core $ARGS\" > /dev/kmsg; modprobe venus_core $ARGS; echo \"venus-bisect: rc=\$?\" > /dev/kmsg'" >/dev/null 2>&1
sleep 15
if up; then echo "RESULT: ALIVE ($ARGS)"; ./jssh "echo $JOAN_PW | sudo -S -p '' dmesg | grep -iE 'venus|stop_at|video-codec' | tail -6" 2>/dev/null | grep -v '^\[sudo'
else echo "RESULT: WEDGED ($ARGS)"; fi
