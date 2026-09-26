#!/bin/sh
# one libcamera capture attempt, with the kernel's view of it
W=${1:-1280}; H=${2:-720}; N=${3:-10}
cd /tmp; rm -f camf*
n=$(dmesg | wc -l)
media-ctl -d /dev/media0 -p 2>/dev/null | grep -E '^- entity.*(ispif|csiphy0|csid0)' | head -4
t0=$(date +%s)
timeout 30 cam -c1 --capture=$N -s width=$W,height=$H,pixelformat=ABGR8888 --file=/tmp/camf#.ppm > /tmp/cam.log 2>&1
echo "cam rc=$? in $(( $(date +%s) - t0 ))s"
grep -vE 'WARN|INFO (Camera|eGL)' /tmp/cam.log | tail -8
ls /tmp/camf* 2>/dev/null | wc -l | sed 's/^/frames written: /'
dmesg | tail -n +$((n+1)) | grep -vE '^\[ *[0-9.]+\]  ' | head -15
grep -E 'csiphy0|csid0|vfe0|ispif' /proc/interrupts | awk '{s=0; for(i=2;i<=9;i++) s+=$i; print $NF, s}'
