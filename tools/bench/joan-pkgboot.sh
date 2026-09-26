#!/bin/sh
# Default-install boot test: install pmaports-built packages on the joan
# bench SD rootfs the way a user would (apk add, which runs mkinitfs and
# boot-deploy), pull the boot.img that the device itself generated, and
# RAM-boot exactly that image. Nothing is flashed.
#   joan-pkgboot.sh <name> <package.apk>...
# Runs on skyforge; the phone is on USB to nym-nest, running pmOS from the SD.
# Needs JOAN_PW on nest in ~/.config/joan-bench-pw and jssh at $J on nest.
set -e
NAME=$1; shift
[ $# -ge 1 ] || { echo "usage: $0 <name> <package.apk>..." >&2; exit 1; }
J=${J:-/tmp/ember-f08d8c5-unpack/jssh}
SERIAL=${SERIAL:-LGUS9986e606d55}
LOG=${LOG:-$(pwd)/pkgboot-$NAME.log}

scp -q "$@" nym-nest-family:/tmp/
APKS=""; for a in "$@"; do APKS="$APKS /home/user/$(basename "$a")"; done
NEST_APKS=""; for a in "$@"; do NEST_APKS="$NEST_APKS /tmp/$(basename "$a")"; done

ssh nym-nest-family "set -e; export JOAN_PW=\$(cat ~/.config/joan-bench-pw); J=$J
for a in $NEST_APKS; do \$J scp \$a user@172.16.42.1:/home/user/; done
echo '== before'; \$J 'ls -la --full-time /boot/boot.img /boot/initramfs /boot/vmlinuz 2>/dev/null; apk info -v 2>/dev/null | grep -E \"^(linux|device)-lge\"'
echo '== apk add'
\$J \"echo \$JOAN_PW | sudo -S -p '' apk add --allow-untrusted $APKS 2>&1\"
echo '== after'; \$J 'ls -la --full-time /boot/boot.img /boot/initramfs /boot/vmlinuz; apk info -v 2>/dev/null | grep -E \"^(linux|device)-lge\"; cat /usr/share/kernel/*/kernel.release 2>/dev/null'
\$J scp user@172.16.42.1:/boot/boot.img ~/joan-images/boot-joan-$NAME.img
sha256sum ~/joan-images/boot-joan-$NAME.img
\$J \"echo \$JOAN_PW | sudo -S -p '' sh -c 'sync && systemd-run --on-active=2 systemctl reboot >/dev/null 2>&1'\" || true
end=\$((SECONDS+300)); while [ \$SECONDS -lt \$end ]; do sudo adb devices | grep -q '$SERIAL.device' && break; sleep 2; done
sudo adb -s $SERIAL reboot bootloader
end=\$((SECONDS+60)); while [ \$SECONDS -lt \$end ]; do sudo fastboot devices | grep -q . && break; sleep 1; done
sudo fastboot boot ~/joan-images/boot-joan-$NAME.img 2>&1 | tail -1
end=\$((SECONDS+200)); while [ \$SECONDS -lt \$end ]; do IF=\$(ip -br link | awk '/^enp0s29u1u5/ {print \$1}' | head -1); if [ -n \"\$IF\" ]; then sudo ip link set \$IF up 2>/dev/null; ip -4 addr show \$IF | grep -q 172.16.42.2 || sudo ip addr add 172.16.42.2/24 dev \$IF 2>/dev/null; fi; ping -c1 -W1 172.16.42.1 >/dev/null 2>&1 && break; done
end=\$((SECONDS+240)); until [ \$SECONDS -ge \$end ] || \$J 'systemctl is-system-running 2>/dev/null | grep -qE \"running|degraded\"' 2>/dev/null; do sleep 5; done
echo '== booted'; \$J 'uname -r; cat /proc/cmdline; systemctl is-system-running; systemctl --failed --no-legend'" 2>&1 | tee "$LOG"
