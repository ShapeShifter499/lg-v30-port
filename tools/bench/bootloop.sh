#!/bin/bash
# N armed RAM-boot cycles of one image; per boot record sound card / modem / failed units.
IMG=$1; N=${2:-6}; SP=$(dirname "$0"); J=${J:-$SP/jssh}; PWF=~/.config/joan-bench-pw
for i in $(seq 1 $N); do
  out=$($SP/ramboot.sh "$IMG" 2>&1 | tail -2 | tr '\n' ' ')
  # wait until 90 s uptime so modem/ADSP settle
  $J "while [ \$(cut -d. -f1 /proc/uptime) -lt 90 ]; do sleep 3; done" 2>/dev/null
  res=$($J "sudo -S -p '' sh -c 'echo card=\$(grep -c LGV30 /proc/asound/cards) svc=\$(qrtr-lookup 2>/dev/null | grep -cE \"^ +[0-9]\") modem_crash=\$(dmesg | grep -c \"crash detected in 4080000\") mm=\$(mmcli -L 2>/dev/null | grep -c Modem) failed=\$(systemctl --failed --no-legend | wc -l) up=\$(cut -d. -f1 /proc/uptime)'" < $PWF 2>&1)
  echo "$(date +%T) boot $i: $res | $out"
done
