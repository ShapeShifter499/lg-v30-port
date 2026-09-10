#!/bin/sh
# Staged module load. Writes progress to STDOUT so the nest captures it live
# even if the SoC resets. ZERO writes to the SD (tmpfs bind-mount).
say() { echo "@@ $(cut -d' ' -f1 /proc/uptime) $*"; }

say "staging modules in tmpfs"
mkdir -p /tmp/modstage
tar xzf /tmp/joan-modules.tgz -C /tmp/modstage || { say "TAR FAILED"; exit 1; }
mountpoint -q /lib/modules && umount /lib/modules
mount --bind /tmp/modstage/lib/modules /lib/modules
say "modules dir: $(ls /lib/modules/) uname=$(uname -r)"

say "adsp firmware:"
ls /lib/firmware/qcom/msm8998/ 2>&1 | tr '\n' ' '
ls /lib/firmware/qcom/msm8998/joan/ 2>&1 | tr '\n' ' '
echo

say "STEP 1: qcom_q6v5_pas"
modprobe qcom_q6v5_pas 2>&1
sleep 6
for r in /sys/class/remoteproc/remoteproc*; do
    [ -e "$r" ] || continue
    say "  $r name=$(cat $r/name 2>&1) state=$(cat $r/state 2>&1)"
done
say "STEP 1 survived"

say "STEP 2: apr"
modprobe apr 2>&1; sleep 3
say "STEP 2 survived; apr children:"; ls /sys/bus/apr/devices/ 2>&1 | tr '\n' ' '; echo

say "STEP 3: q6 core stack"
for m in q6core snd-q6dsp-common q6afe q6afe-dai q6asm q6asm-dai q6adm q6routing; do
    modprobe "$m" 2>&1 && say "  loaded $m" || say "  FAILED $m"
done
sleep 3
say "STEP 3 survived"

say "STEP 4: codecs"
for m in wcd934x snd-soc-wcd934x snd-soc-tfa989x snd-soc-es9218p; do
    modprobe "$m" 2>&1 && say "  loaded $m" || say "  FAILED $m"
done
sleep 3
say "STEP 4 survived"

say "STEP 5: machine driver"
modprobe snd-soc-qcom-common 2>&1
modprobe snd-soc-sdm845 2>&1
sleep 6
say "STEP 5 survived"

say "CARDS:"; cat /proc/asound/cards 2>&1
say "arecord -l:"; arecord -l 2>&1
say "DONE"
