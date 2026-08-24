#!/bin/sh
# Temporary live test: replace only snd_soc_wcd934x with a matching-vermagic
# K2-initialization build. No rootfs write; reboot restores the stock module.
# Written-by: Aurel Nymvale (agent-aurel)
# Agent-harness: Hermes-Agent:gpt-5.6-terra
# Date: 2026-08-24
# DO NOT run until the user has approved the brief audio-card rebind.

set -u
MODULE=/tmp/snd-soc-wcd934x-k2.ko
ASKPASS=/tmp/askpass-joan.sh

do_sudo() {
  SUDO_ASKPASS="$ASKPASS" sudo -A "$@"
}

restore_stock() {
  echo '== recovery: restore packaged WCD934x codec module =='
  do_sudo rmmod snd_soc_sdm845 2>/dev/null || true
  do_sudo rmmod snd_soc_wcd934x 2>/dev/null || true
  do_sudo modprobe snd_soc_wcd934x 2>/dev/null || true
  do_sudo modprobe snd_soc_sdm845 2>/dev/null || true
}

[ -x "$ASKPASS" ] || { echo "missing $ASKPASS"; exit 2; }
[ -r "$MODULE" ] || { echo "missing $MODULE"; exit 2; }

# Avoid an active sound-server stream keeping the card busy during unbind.
pkill -f wireplumber 2>/dev/null || true
pkill -f pipewire 2>/dev/null || true
pkill -f pulseaudio 2>/dev/null || true

echo '== unload machine card =='
do_sudo rmmod snd_soc_sdm845 || exit 1

echo '== unload packaged WCD934x codec component =='
if ! do_sudo rmmod snd_soc_wcd934x; then
  echo 'codec unload failed; restoring machine card'
  do_sudo modprobe snd_soc_sdm845 || true
  exit 1
fi

echo '== load temporary K2 codec module =='
if ! do_sudo insmod "$MODULE"; then
  echo 'temporary module load failed'
  restore_stock
  exit 1
fi

echo '== rebind machine card =='
if ! do_sudo modprobe snd_soc_sdm845; then
  echo 'machine-card rebind failed'
  restore_stock
  exit 1
fi

echo '== verify card and the programmed Class-H K2 coefficient =='
cat /proc/asound/cards
# Read-only debugfs query. 0c0b must report 60 after this test module probes.
# A full sequential read is required by this regmap debugfs implementation.
do_sudo sh -c "cat /sys/kernel/debug/regmap/217\\:250\\:1\\:0/registers | grep '^0c0b:'"
echo '== temporary K2 module active; run the earpiece listening test next =='
