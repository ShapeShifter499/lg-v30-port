# NEXT SESSION: port the ES9218P power-state machine

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-09-14

STANDING APPROVAL (Lance): always look at the code and reverse engineer stock
ROM/kernel wherever it helps the port.

## Read first

`docs/2026-09-13-headset-detect-mbhc-armed-but-blind.md` — the full root-cause
record. **Do not re-open MBHC.** It is not broken; its registers are
byte-identical to the stock kernel and the raw INTR_PIN1_STATUS latches never
move because no electrical change reaches them.

## The task

Mainline's `sound/soc/codecs/es9218p.c` treats Low Power Bypass as a **pin
transition**: write AMP_CONFIG, set MODE2, drop RESETb. joan's downstream
driver treats it as a **state**, and mainline has no equivalent of any of it.

Port from LG's `sound/soc/codecs/es9218.c` (in
`~/vibe-coding-projects/coding/android_kernel_lge_msm8998`):

- `es9218_power_state` — `ESS_PS_CLOSE` / `IDLE` / `BYPASS` / `HIFI`, and the
  transitions between them
- `__es9218_sabre_headphone_on()` / `__es9218_sabre_headphone_off()`
- `es9218_sabre_audio_idle()` / `es9218_sabre_audio_active()`
- `es9218_sabre_bypass2hifi()` (706) and `es9218_sabre_hifi2bypass()` (855)

r20 already ports the one-register part of `hifi2bypass` (AMP_CONFIG 0 ->
0x01) and it is **verified live but insufficient** — keep it, since 0 powers
the amplifier block down entirely, but it is not the fix on its own.

## Pass criteria — two independent observables

1. **Audio**: the `Headphones` UCM device (WCD -> ES9218P bypass -> jack)
   becomes audible. It is silent today; `HeadphonesHiFi` is audible and is the
   positive control.
2. **Detection**: `mbhc sw intr` in /proc/interrupts moves on a physical
   replug, and the `Headphone Jack` kcontrol goes `on`.

Both should follow from the same fix. If only (1) appears, there is a second
and genuinely separate MBHC problem — but it would then be diagnosed against a
live analog path for the first time.

## Bench protocol (learned the hard way)

- **Reboot before each audio measurement.** ALSA control state accumulates; a
  tone test that worked earlier went silent on BOTH bursts after ~9 h uptime
  with `Headphone Playback Switch` left `off`.
- **Positive-control every harness.** Include the known-audible
  `HeadphonesHiFi` burst; read back `AMP_CONFIG` mid-stimulus (00 -> 01/02)
  before trusting anything downstream.
- **Cross order AND pitch** against path in any A/B by ear. Both must vary
  independently of the treatment or the result is uninterpretable.
- **Verify installs by module hash, never by apk's exit status.** A killed
  `apk` rolls back the transaction and still exits 0. `snd-soc-es9218p.ko.zst`
  must change.
- Do not run a long `apk` inside an ssh with a short timeout; the install dies
  with the connection and can leave the phone thrashing for minutes.
- `hw:0,1` is the working capture FE; `hw:0,0` is playback.
- nest needs `sudo ip link set enp0s29u1u5 up` + `ip addr add 172.16.42.2/24`
  after **every** phone boot.

## State at handoff

- kernel `joan/es9218p-bypass-ampcfg` @ `f7695e7515dd` (pushed) = r19 + the
  AMP_CONFIG change. Base it on this.
- pmaports `joan/readme-build-guide` @ pkgrel 20 (pushed to `ghjoan`).
- Phone rootfs has r20 installed; images staged on nest under
  `~/joan-test-assets/r20-20260913/`.
- Builds are ~10 min warm (ccache on the HDD, `hash_dir=false`, 50 G).
