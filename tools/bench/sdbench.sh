#!/bin/sh
# SD benchmark: run as root. Writes a 16 MiB test file in /var/tmp and removes it.
T=/sys/kernel/tracing; F=/var/tmp/sdbench.$$
now() { cat /proc/uptime | cut -d' ' -f1; }
rate() { awk -v b=$1 -v s=$2 -v e=$3 'BEGIN{d=e-s; printf "%.2f MB/s (%.2fs)", b/1048576/d, d}'; }
echo "kernel $(uname -r)  sched $(cat /sys/block/mmcblk0/queue/scheduler)"
grep -E "Timeout|Auto" /sys/kernel/debug/mmc0/err_stats | tr -s ' \t' ' '
echo 3 > /proc/sys/vm/drop_caches
echo > $T/trace; echo 1 > $T/events/mmc/mmc_request_start/enable
s=$(now); dd if=/dev/zero of=$F bs=1M count=16 oflag=direct conv=fsync 2>/dev/null; e=$(now)
echo 0 > $T/events/mmc/mmc_request_start/enable
echo "seq write 16MiB O_DIRECT: $(rate 16777216 $s $e)"
echo "  cmds during write: CMD24(single)=$(grep -c 'cmd_opcode=24 ' $T/trace) CMD25(multi)=$(grep -c 'cmd_opcode=25 ' $T/trace)"
rm -f $F; sync
s=$(now); dd if=/dev/mmcblk0p2 of=/dev/null bs=4M count=16 skip=30000 iflag=direct 2>/dev/null; e=$(now)
echo "seq read 64MiB O_DIRECT: $(rate 67108864 $s $e)"
s=$(now); i=0; while [ $i -lt 200 ]; do dd if=/dev/mmcblk0p2 of=/dev/null bs=4k count=1 skip=$(( (i*7919 % 40000) * 1000 )) iflag=direct 2>/dev/null; i=$((i+1)); done; e=$(now)
awk -v s=$s -v e=$e 'BEGIN{printf "4K random read x200: %.1f IOPS (%.2f ms avg)\n", 200/(e-s), (e-s)*5}'
cat /proc/pressure/io | head -1
grep -E "Timeout|Auto" /sys/kernel/debug/mmc0/err_stats | tr -s ' \t' ' '
