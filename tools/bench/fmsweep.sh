#!/bin/sh
# FM band sweep through /dev/radio0: signal per channel, then seeks (run as root)
R=/dev/radio0
exec 3<$R
k=87900
while [ $k -le 107900 ]; do
	f=$(awk "BEGIN{printf \"%.1f\", $k/1000}")
	v4l2-ctl -d $R -f $f >/dev/null 2>&1
	s=$(v4l2-ctl -d $R -T | awk -F'[:%]' '/Signal/ {gsub(/ /,"",$2); print $2}')
	st=$(v4l2-ctl -d $R -T | awk -F: '/Available/ {gsub(/^ +| +$/,"",$2); print $2}')
	echo "$f $s $st"
	k=$((k + 200))
done | sort -k2 -n -r | head -15
echo "== seeks up from 87.9, wrap"
v4l2-ctl -d $R -f 87.9 >/dev/null
for i in 1 2 3 4 5 6; do v4l2-ctl -d $R --freq-seek=dir=1,wrap=1 2>&1 | tail -1; v4l2-ctl -d $R -F | awk '{print $NF, $(NF-1)}' | tail -1; done
exec 3<&-
