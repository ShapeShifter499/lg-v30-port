#!/bin/sh
# Package a kernel build outdir, install its modules on the joan bench SD
# rootfs (via the running pmOS), and RAM-boot it with fastboot.
#   joan-testboot.sh <outdir> <image-name> [extra cmdline]
# Assumes pmOS is running on the phone and nym-nest has jssh + the r26
# on-device initramfs in /tmp/ember-f08d8c5-unpack.
set -e
D=$1; NAME=$2; EXTRA=${3:-}
: "${JOAN_PW:?export JOAN_PW, the bench pmOS user password}"
R=$(cat "$D/include/config/kernel.release")
SP=${SP:-/tmp/joan-bench}; mkdir -p "$SP"
ST=$SP/mods-$NAME
rm -rf "$ST"
make -s -C ~/vibe-coding-projects/coding/linux-mainline-v30 O="$D" ARCH=arm64 \
	CROSS_COMPILE=aarch64-linux-gnu- CC="ccache aarch64-linux-gnu-gcc" INSTALL_MOD_PATH="$ST" INSTALL_MOD_STRIP=1 modules_install </dev/null
rm -f "$ST/lib/modules/$R/build" "$ST/lib/modules/$R/source"
tar -C "$ST/lib/modules" --owner=0 --group=0 -czf "$SP/mods-$NAME.tgz" "$R"
cat "$D/arch/arm64/boot/Image.gz" "$D/arch/arm64/boot/dts/qcom/msm8998-lge-joan.dtb" > "$SP/kernel-$NAME"
scp -q "$SP/mods-$NAME.tgz" "$SP/kernel-$NAME" nym-nest-family:/tmp/ember-f08d8c5-unpack/
ssh nym-nest-family "set -e; cd /tmp/ember-f08d8c5-unpack
mkbootimg --header_version 0 --kernel kernel-$NAME --ramdisk initramfs-r26-ondevice \
	--pagesize 0x00001000 --base 0x00000000 --kernel_offset 0x00008000 \
	--ramdisk_offset 0x02000000 --second_offset 0x00f00000 --tags_offset 0x00000100 \
	--board '' --cmdline 'panic=5 pmos.force-partition-resize ipa.lowmem=1 log_buf_len=8M $EXTRA' \
	-o ~/joan-images/boot-joan-$NAME.img
./jssh scp mods-$NAME.tgz user@172.16.42.1:/home/user/
./jssh \"echo $JOAN_PW | sudo -S -p '' sh -c 'rm -rf /lib/modules/$R; tar -C /lib/modules -xzf /home/user/mods-$NAME.tgz && depmod -a $R && sync && systemd-run --on-active=2 systemctl reboot >/dev/null 2>&1'\"
end=\$((SECONDS+300)); while [ \$SECONDS -lt \$end ]; do sudo adb devices | grep -q 'LGUS9986e606d55.device' && break; ping -c3 -W1 127.0.0.1 >/dev/null; done
sudo adb -s LGUS9986e606d55 reboot bootloader
sudo fastboot boot ~/joan-images/boot-joan-$NAME.img 2>&1 | tail -1
end=\$((SECONDS+200)); while [ \$SECONDS -lt \$end ]; do IF=\$(ip -br link | awk '/^enp0s29u1u5/ {print \$1}' | head -1); if [ -n \"\$IF\" ]; then sudo ip link set \$IF up 2>/dev/null; ip -4 addr show \$IF | grep -q 172.16.42.2 || sudo ip addr add 172.16.42.2/24 dev \$IF 2>/dev/null; fi; ping -c1 -W1 172.16.42.1 >/dev/null 2>&1 && break; done
end=\$((SECONDS+240)); until [ \$SECONDS -ge \$end ] || ./jssh 'systemctl is-system-running 2>/dev/null | grep -qE \"running|degraded\"' 2>/dev/null; do ping -c5 -W1 127.0.0.1 >/dev/null; done
./jssh 'uname -r; systemctl is-system-running'"
