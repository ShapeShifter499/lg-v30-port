#!/bin/sh
# Close/reopen race: viewfinder sessions back to back with a fixed gap.
# No raw role, no exposure writes -- only the open/close timing varies.
N=${1:-30}; GAP=${2:-0}
L=/home/user/camrace.log; echo "$(date +%T) start N=$N gap=$GAP" >> $L; sync
i=0
while [ $i -lt $N ]; do
	i=$((i+1))
	timeout 15 cam -c1 --capture=5 -s width=640,height=480,pixelformat=ABGR8888 >/dev/null 2>&1
	echo "$(date +%T) gap=$GAP run $i rc=$?" >> $L; sync
	[ "$GAP" = 0 ] || sleep $GAP
done
echo "$(date +%T) DONE gap=$GAP" >> $L; sync
