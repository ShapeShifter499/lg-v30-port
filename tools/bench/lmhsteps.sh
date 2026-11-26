#!/bin/sh
# Replay LMh bring-up steps; watch the LMh request (b04) and the real gold clock.
R=/home/user/regdump M=/home/user/cpumhz2
m() { echo "   $1: $($M 4 0.7)  b04 silver=$($R 179c1b04 1 | cut -d' ' -f2) gold=$($R 179c3b04 1 | cut -d' ' -f2)"; }
m baseline
for st in $*; do
	rmmod lmhprof 2>/dev/null
	insmod /home/user/lmhprof.ko steps=$st
	dmesg | grep lmhprof | tail -n 5 | sed 's/^/      /'
	sleep 2; m "after steps=$st"
done
