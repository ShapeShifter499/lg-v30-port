#!/bin/sh
# Phone-side codec DAPM bring-up + audible tone, Boot 24a.
# Written-by: Ember Nymbrand (agent-ember)
# Agent-harness: Claude-Code:claude-opus-5
# Date: 2026-08-21
#
# Three outputs are set up and played in sequence so one boot tells us which
# of joan's analog paths is actually wired to something audible:
#   EAR  (RX INT0 -> EAR PA)          earpiece receiver
#   HPHL (RX INT1 -> HPHL PA)  \      headphone jack, through the ES9218P
#   HPHR (RX INT2 -> HPHR PA)  /      held in Low Power Bypass by DT hogs
#
# Nothing is set with 2>/dev/null: every amixer call reports its own result,
# because a control that silently does not exist looks exactly like success.
LOG=/var/log/joan-dapm.txt
# NOTE: "RXn Digital Volume" is SOC_SINGLE_S8_TLV(-84..40): the control value is an
# offset from -84 dB, so 0 means -84 dB (silence) and 84 means 0 dB.

set_ctl() {
    _n="$1"; _v="$2"
    if out=$(amixer -c 0 cset name="$_n" "$_v" 2>&1); then
        echo "  OK   $_n = $_v  -> $(echo "$out" | grep -E '^  : values' | head -1)"
    else
        echo "  FAIL $_n = $_v  -> $(echo "$out" | head -2 | tr '\n' ' ')"
    fi
}

{
echo "== dapm seq start $(date +%s) =="
echo "SEQ_MARK_24A" > /var/log/joan-seqmark.txt
sync

echo "== ES9218P mode pins (expect power=hi, hifi-mode2=hi, reset-n=lo) =="
if [ -r /sys/kernel/debug/gpio ]; then
    grep -iE "es9218p|pm8998|pmi8998" /sys/kernel/debug/gpio | head -20
else
    echo "  (no /sys/kernel/debug/gpio; is debugfs mounted?)"
fi

echo
echo "== routing: q6 front end -> SLIMBUS_0_RX =="
set_ctl "SLIMBUS_0_RX Audio Mixer MultiMedia1" 1

echo
echo "== codec: both SLIM RX channels from AIF1_PB (stereo) =="
set_ctl "SLIM RX0 MUX" AIF1_PB
set_ctl "SLIM RX1 MUX" AIF1_PB

echo
echo "== codec: interpolator input select =="
set_ctl "RX INT0_1 MIX1 INP0" RX0     # EAR   <- left
set_ctl "RX INT1_1 MIX1 INP0" RX0     # HPHL  <- left
set_ctl "RX INT2_1 MIX1 INP0" RX1     # HPHR  <- right

echo
echo "== codec: interpolator main path enable =="
set_ctl "RX INT0_1 INTERP" "RX INT0_1 MIX1"
set_ctl "RX INT1_1 INTERP" "RX INT1_1 MIX1"
set_ctl "RX INT2_1 INTERP" "RX INT2_1 MIX1"

echo
echo "== codec: DEM mux to the class-H DSM output =="
set_ctl "RX INT0 DEM MUX" CLSH_DSM_OUT
set_ctl "RX INT1 DEM MUX" CLSH_DSM_OUT
set_ctl "RX INT2 DEM MUX" CLSH_DSM_OUT

echo
echo "== gains: digital 0 dB (control 84!), analog conservative =="
set_ctl "RX0 Digital Volume" 84   # 84 == 0 dB: the control is an OFFSET FROM -84 dB
set_ctl "RX1 Digital Volume" 84
set_ctl "RX2 Digital Volume" 84
set_ctl "HPHL Volume" 12
set_ctl "HPHR Volume" 12
set_ctl "EAR PA Volume" 2

echo
echo "== resulting DAPM endpoint state =="
for w in EAR HPHL HPHR "EAR PA" "HPHL PA" "HPHR PA" "RX INT0 DAC" "RX INT1 DAC" "RX INT2 DAC"; do
    f="/sys/kernel/debug/asoc/LG-V30/dapm/$w"
    [ -r "$f" ] && echo "  $w: $(head -1 "$f")" || echo "  $w: (no debugfs node)"
done
sync

echo
echo "== PLAY: 6 s tone, L=440Hz R=660Hz, five times with 8 s gaps =="
echo "   (repeated so a missed listening window does not cost a boot)"
n=1
while [ $n -le 5 ]; do
    echo "== tone $n/5 start $(date +%s) =="
    timeout 20 aplay -D hw:0,0 /tmp/tone.wav
    echo "tone $n rc=$? at $(date +%s)"
    sync
    n=$((n+1))
    [ $n -le 5 ] && sleep 8
done

echo
echo "== post-play mixer readback (did anything reset?) =="
amixer -c 0 cget name="RX INT1 DEM MUX" 2>&1 | grep -E "^  : values"
amixer -c 0 cget name="HPHL Volume" 2>&1 | grep -E "^  : values"
echo "== dapm seq end $(date +%s) =="
} > $LOG 2>&1
sync
