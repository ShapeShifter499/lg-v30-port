#!/bin/bash
# validate.sh <tag>: wait for the modem to settle, run validate-remote.sh on the phone,
# write <tag>-validate.txt to $OUT (default: cwd) and print a one-line dmesg summary.
# Runs on nym-nest (phone on USB there); needs jssh and ~/.config/joan-bench-pw.
W=$(cd "$(dirname "$0")" && pwd); OUT=${OUT:-$PWD}; export JOAN_PW=$(cat ~/.config/joan-bench-pw); J=/tmp/ember-f08d8c5-unpack/jssh
end=$((SECONDS+180)); until [ $SECONDS -ge $end ] || timeout 10 $J "mmcli -m any 2>/dev/null | grep -qE 'state: .*(registered|connected)'" 2>/dev/null; do sleep 5; done
timeout 20 $J scp $W/validate-remote.sh user@172.16.42.1:/tmp/v.sh
timeout 150 $J "JOAN_PW='$JOAN_PW' sh /tmp/v.sh" > $OUT/$1-validate.txt 2>&1
sed -n '/== rmem/,/== dmesg/p' $OUT/$1-validate.txt
d=$OUT/$1-validate.txt
printf 'dmesg: WARN=%s OSMfail=%s ASoC=%s set_fmt=%s zap=%s gpu-err=%s ath10k-err=%s ipa-err=%s errfail=%s\n' \
 $(grep -ac 'WARNING' $d) $(grep -ac 'Cannot setup the OSM' $d) $(grep -ac 'ASoC error' $d) $(grep -ac set_fmt $d) \
 $(grep -aic 'zap' $d) $(grep -aiE 'adreno|msm_gpu|a5xx' $d | grep -aicE 'err|fail|timeout') \
 $(grep -aiE 'ath10k' $d | grep -aicE 'err|fail') $(grep -aiE 'ipa ' $d | grep -aicE 'err|fail') $(grep -aciE 'error|fail' $d)
