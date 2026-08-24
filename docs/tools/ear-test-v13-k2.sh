#!/bin/sh
# Earpiece listen test #13 — full WCD934x route after K2 Class-H init change.
# Author: Aurel Nymvale; harness: Hermes-Agent:gpt-5.6-terra; date: 2026-08-24
# Requires /tmp/ear-tone48.wav (48 kHz mono tone).

set -u
M='amixer -c 0 sset'

restore_pulse() {
  rm -f "$HOME/.config/pulse/client.conf"
  if [ -f "$HOME/.config/pulse/client.conf.bak-ear" ]; then
    mv "$HOME/.config/pulse/client.conf.bak-ear" "$HOME/.config/pulse/client.conf"
  fi
}

teardown() {
  $M 'RX INT0 DEM MUX' NORMAL_DSM_OUT >/dev/null 2>&1 || true
  $M 'RX INT0_2 INTERP' ZERO >/dev/null 2>&1 || true
  $M 'RX INT0_2 MUX' ZERO >/dev/null 2>&1 || true
  $M 'RX INT0_1 INTERP' ZERO >/dev/null 2>&1 || true
  $M 'RX INT0_1 MIX1 INP0' ZERO >/dev/null 2>&1 || true
  $M 'SLIM RX0 MUX' ZERO >/dev/null 2>&1 || true
  $M 'SLIMBUS_0_RX Audio Mixer MultiMedia1' off >/dev/null 2>&1 || true
  restore_pulse
}

fail() { echo "!! $* — aborting"; exit 1; }
check_enum() {
  control=$1 expected=$2
  actual=$(amixer -c 0 sget "$control" 2>&1)
  case "$actual" in
    *"$expected"*) echo "ok: $control = $expected" ;;
    *) fail "$control readback was: $actual" ;;
  esac
}
check_numid() {
  numid=$1 expected=$2 label=$3
  actual=$(amixer -c 0 cget "numid=$numid" 2>/dev/null | grep -m1 ': values=')
  case "$actual" in
    *"values=$expected"*) echo "ok: $label = $expected" ;;
    *) fail "$label readback was: $actual" ;;
  esac
}

trap teardown EXIT INT TERM

[ -r /tmp/ear-tone48.wav ] || fail 'missing /tmp/ear-tone48.wav'
echo '== stop sound daemons and prevent PulseAudio autospawn =='
pkill -f wireplumber 2>/dev/null || true
pkill -f pipewire 2>/dev/null || true
pkill -f pulseaudio 2>/dev/null || true
mkdir -p "$HOME/.config/pulse"
if [ -f "$HOME/.config/pulse/client.conf" ]; then
  cp "$HOME/.config/pulse/client.conf" "$HOME/.config/pulse/client.conf.bak-ear"
fi
echo 'autospawn = no' > "$HOME/.config/pulse/client.conf"

# Explicitly enforce the known-safe 0 dB digital gain and +6 dB EAR PA gain.
amixer -c 0 cset numid=13 84 >/dev/null || fail 'cannot set RX0 Digital Volume'
amixer -c 0 cset numid=4 4 >/dev/null || fail 'cannot set EAR PA Volume'
check_numid 13 84 'RX0 Digital Volume (0 dB)'
check_numid 4 4 'EAR PA Volume (+6 dB)'

echo '== reset then configure complete earpiece path =='
$M 'SLIMBUS_0_RX Audio Mixer MultiMedia1' off >/dev/null
$M 'SLIM RX0 MUX' ZERO >/dev/null
$M 'RX INT0_1 MIX1 INP0' ZERO >/dev/null
$M 'RX INT0_1 INTERP' ZERO >/dev/null
$M 'RX INT0_2 MUX' ZERO >/dev/null
$M 'RX INT0_2 INTERP' ZERO >/dev/null
$M 'RX INT0 DEM MUX' NORMAL_DSM_OUT >/dev/null

$M 'SLIMBUS_0_RX Audio Mixer MultiMedia1' on >/dev/null
$M 'SLIM RX0 MUX' AIF1_PB >/dev/null
$M 'RX INT0_1 MIX1 INP0' RX0 >/dev/null
$M 'RX INT0_1 INTERP' 'RX INT0_1 MIX1' >/dev/null
$M 'RX INT0_2 MUX' RX0 >/dev/null
$M 'RX INT0_2 INTERP' 'RX INT0_2 MUX' >/dev/null
$M 'RX INT0 DEM MUX' CLSH_DSM_OUT >/dev/null

check_enum 'SLIMBUS_0_RX Audio Mixer MultiMedia1' '[on]'
check_enum 'SLIM RX0 MUX' AIF1_PB
check_enum 'RX INT0_1 MIX1 INP0' RX0
check_enum 'RX INT0_1 INTERP' 'RX INT0_1 MIX1'
check_enum 'RX INT0_2 MUX' RX0
check_enum 'RX INT0_2 INTERP' 'RX INT0_2 MUX'
check_enum 'RX INT0 DEM MUX' CLSH_DSM_OUT

echo '== earpiece tone begins in 5 seconds; listen continuously (~26 seconds) =='
sleep 5
aplay -D plughw:0,0 -q /tmp/ear-tone48.wav
rc=$?
echo "aplay exit=$rc"
[ "$rc" -eq 0 ] || fail 'aplay failed'
echo '== completed; route and PulseAudio autospawn are being restored =='
