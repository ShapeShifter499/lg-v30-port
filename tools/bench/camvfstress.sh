#!/bin/sh
# viewfinder-only open/close stress (the path a camera app takes)
L=/home/user/camvf.log; : > $L
step() { echo "$(date +%T) $*" >> $L; sync; }
i=0
while [ $i -lt ${1:-40} ]; do
	i=$((i+1))
	timeout 15 cam -c1 --capture=15 -s width=1280,height=720,pixelformat=ABGR8888 >/dev/null 2>&1
	step "run $i rc=$?"
	sleep 2
done
step DONE
