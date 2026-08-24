#!/bin/sh
# Restore the packaged WCD934x codec after the temporary K2 experiment.
# No rootfs write; this is a runtime rebind only.
# Written-by: Aurel Nymvale (agent-aurel)
# Agent-harness: Hermes-Agent:gpt-5.6-terra
# Date: 2026-08-24.
set -u
ASKPASS=/tmp/askpass-joan.sh
do_sudo() { SUDO_ASKPASS="$ASKPASS" sudo -A "$@"; }

[ -x "$ASKPASS" ] || { echo "missing $ASKPASS"; exit 2; }
pkill -f wireplumber 2>/dev/null || true
pkill -f pipewire 2>/dev/null || true
pkill -f pulseaudio 2>/dev/null || true

echo '== unload machine card =='
do_sudo rmmod snd_soc_sdm845 || exit 1

echo '== unload temporary WCD934x module =='
if ! do_sudo rmmod snd_soc_wcd934x; then
  echo 'codec unload failed; attempting machine-card rebind'
  do_sudo modprobe snd_soc_sdm845 || true
  exit 1
fi

echo '== restore packaged WCD934x module =='
if ! do_sudo modprobe snd_soc_wcd934x; then
  echo 'packaged codec module load failed'
  exit 1
fi

echo '== rebind machine card =='
if ! do_sudo modprobe snd_soc_sdm845; then
  echo 'machine-card rebind failed'
  exit 1
fi

echo '== verify restored card and stock K2 =='
cat /proc/asound/cards
do_sudo sh -c "cat /sys/kernel/debug/regmap/217\\:250\\:1\\:0/registers | grep '^0c0b:'"
echo '== packaged codec module restored =='
