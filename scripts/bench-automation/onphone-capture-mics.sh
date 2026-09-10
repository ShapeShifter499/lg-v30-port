#!/bin/sh
# Correct order: UCM EnableSequence FIRST, then neutralise TX COPP Topology.
# UCM sets SM_ECNS, which makes ADM_CMD_DEVICE_OPEN_V5 fail closed (-22).
OUT=/tmp/joan-capture; rm -rf "$OUT"; mkdir -p "$OUT"
exec > "$OUT/capture.log" 2>&1
set -x
for spec in "Mic 1" "Headset 1" "DualMic 2" "Camcorder 2"; do
    dev=${spec% *}; ch=${spec#* }
    alsaucm -c 0 set _verb HiFi set _enadev "$dev" 2>&1
    amixer -c0 cset name='TX COPP Topology' None >/dev/null 2>&1
    amixer -c0 contents > "$OUT/mixer-$dev.txt" 2>&1
    arecord -D hw:0,1 -f S16_LE -r 48000 -c "$ch" -d 5 "$OUT/$dev.wav" 2>&1
    alsaucm -c 0 set _verb HiFi set _disdev "$dev" 2>/dev/null
done
amixer -c0 cset name='TX COPP Topology' None >/dev/null 2>&1
ls -l "$OUT"
