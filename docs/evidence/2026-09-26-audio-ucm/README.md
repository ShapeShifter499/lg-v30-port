# 2026-09-26 — no sound on a default install: UCM routing and missing WirePlumber settings

Reported by Lance: Firefox/YouTube played with no sound on the r28/r29 default
install.

## Cause

1. **UCM profile rejected.** `alsa-ucm-conf-lge-joan` r4 enabled nothing at the
   HiFi verb level and did all routing in the devices. PipeWire's ACP probes a
   UCM profile by setting only the verb and opening the PCMs. A q6asm frontend
   with no backend routed refuses to open ("no backend DAIs enabled for
   MultiMedia1"; `Invalid argument`), and capture additionally needs at least
   one SLIMbus TX port enabled or wcd934x has nothing to stream (ENOENT from the
   plug PCM). All 20 HiFi profiles were marked "not supported"
   (`wireplumber-before.txt`: only `off` and `pro-audio`), WirePlumber fell back
   to Pro Audio, which does no routing, and nothing played.
2. **Priorities.** Headphones (200) and the headset mic (200) outranked the
   loudspeaker and the built-in mic; with no working jack detection the sound
   server would have picked outputs that are not there.
3. **WirePlumber tuning never packaged.** `53-joan-driver-priority.conf` and
   `54-joan-no-mmap.conf`, measured on 2026-09-11, lived only in `/etc` on the
   old bench SD card. A fresh install ran pmaports' `51-qcom.conf`, whose
   4096-frame periods exceed q6asm-dai's 4096-byte capture limit.

## Fix (pmaports joan/readme-build-guide 1c56389204)

- alsa-ucm-conf-lge-joan r5: the verb routes MultiMedia1 -> loudspeaker and the
  built-in mic path (ADC1 -> DEC6 -> TX6 -> SLIMBUS_0_TX -> MultiMedia2); other
  devices swap the default out and back. Loudspeaker and built-in mic rank
  highest.
- device-lge-joan r19 / -h932 r12: ship the two WirePlumber drop-ins.

## Verified

ACP now offers all 20 HiFi profiles (best "HiFi (Mic, Speaker)"), WirePlumber
creates "Built-in Audio Loudspeaker (TFA9872, tertiary MI2S)" and "Built-in mic
(bottom, WCD9340 AMIC1)", and a test tone drives the playback PCM to RUNNING
(S16_LE, 2 ch, 48 kHz).

## Not yet verified

- Sound by ear (Lance).
- Capture: with the greeter's PipeWire alive (the phone at the login screen),
  every captured sample is exactly zero, even on a raw `arecord` with the whole
  DAPM path powered. The 2026-09-11 investigation saw the same thing whenever a
  sound daemon held `controlC0`. The real test is capture inside a logged-in
  session, where the greeter's stack has exited.
