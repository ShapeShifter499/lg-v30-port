#!/system/bin/sh
# Lineage (4.4) baseline. Reads are raw + read-only; the only write is one temp file on the SD rootfs.
up() { cut -d' ' -f1 /proc/uptime; }
rate() { awk -v b=$1 -v s=$2 -v e=$3 'BEGIN{printf "%.2f MB/s (%.2fs)", b/(e-s), e-s}'; }
echo "kernel $(uname -r) sd-sched $(cat /sys/block/mmcblk0/queue/scheduler) ufs-sched $(cat /sys/block/sda/queue/scheduler)"
sync; echo 3 > /proc/sys/vm/drop_caches
s=$(up); dd if=/dev/block/mmcblk0p2 of=/dev/null bs=4194304 count=16 skip=30000 2>/dev/null; e=$(up); echo "SD  seq read 64MiB : $(rate 64 $s $e)"
echo 3 > /proc/sys/vm/drop_caches
s=$(up); i=0; while [ $i -lt 200 ]; do dd if=/dev/block/mmcblk0p2 of=/dev/null bs=4096 count=1 skip=$(( (i*7919 % 40000) * 1000 )) 2>/dev/null; i=$((i+1)); done; e=$(up)
awk -v s=$s -v e=$e 'BEGIN{printf "SD  4K random read x200: %.1f IOPS\n", 200/(e-s)}'
M=/data/local/tmp/p2rw; mkdir -p $M
if mount -t ext4 -o rw,noatime /dev/block/mmcblk0p2 $M; then
  sync; s=$(up); dd if=/dev/zero of=$M/var/tmp/lineage-sdbench bs=1048576 count=16 conv=fsync 2>/dev/null; e=$(up)
  echo "SD  seq write 16MiB (fsync): $(rate 16 $s $e)"; rm -f $M/var/tmp/lineage-sdbench; sync; umount $M && echo "SD  unmounted clean"
else echo "SD  rw mount failed; write test skipped"; fi
echo 3 > /proc/sys/vm/drop_caches
s=$(up); dd if=/dev/block/sda of=/dev/null bs=4194304 count=64 skip=2000 2>/dev/null; e=$(up); echo "UFS seq read 256MiB: $(rate 256 $s $e)"
echo 3 > /proc/sys/vm/drop_caches
s=$(up); for k in 1 2 3 4; do dd if=/dev/block/sda of=/dev/null bs=1048576 count=256 skip=$((30000+k*5000)) 2>/dev/null & done; wait; e=$(up); echo "UFS 4 readers x256MiB: $(rate 1024 $s $e) aggregate"
cat /sys/devices/soc/1da4000.ufshc/power_info/* 2>/dev/null | head -0
