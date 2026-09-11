# Handoff: joan audio — 2026-09-11 (Ember → next session)

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-09-11

Supersedes `HANDOFF-2026-09-10-next-session.md`. Read this first, then the
three notes it points at.

## Headline

Audio on this port went from "capture records digital silence" to **working
microphones, clean playback through PipeWire, and a low-power headphone path
that was never reachable before**. Everything below was verified on hardware,
most of it confirmed by ear.

Still broken: **MBHC jack detection**, and everything downstream of it — the
in-line mic and its button.

## What works now

* **Microphone capture.** Tone-verified acoustically: a 1 kHz tone from the
  loudspeaker appears at 1 kHz in the recording and vanishes when the ADC
  source is cut. ADC1 (bottom) 44733x its neighbouring bins, ADC3 (top) 6561x.
* **Playback is clean.** "Clear tone, no wobble" after the buffer fix. A 45 s
  file plays in 46.0 s — real time, no drift, zero errors.
* **PipeWire + WirePlumber + pipewire-pulse**, PulseAudio removed, phosh
  intact.
* **Low Power Bypass.** With the ES9218P in bypass, the WCD9340's own
  HPHL/HPHR amplifiers drive the headphone jack audibly. The Quad DAC can be
  powered down and engaged on demand.

## The three things that mattered most

1. **Buffer parameters must be MEASURED from this device.** Read `hw_params`
   off a working `aplay`/`arecord`: playback `6240 x 4`, capture `1920 x 8`,
   plus `disable-tsched` and `disable-mmap`. Every guessed value was wrong —
   pmaports' shared `51-qcom.conf` asks for a 4096-*frame* period while
   `q6asm-dai.c` caps capture at 4096 *bytes*, and Android's HAL numbers do not
   transfer because tinyALSA sets `stop_threshold = INT_MAX` and never lets
   ALSA halt on underrun.
2. **`TX COPP Topology SM_ECNS` fails the ALSA capture open.** This was the
   real "pulseaudio blocker": killing the daemon only stopped anything from
   applying the bad topology. Fixed to `None` in the UCM.
3. **`hph_switch` is the ES9218P's MODE2 pin**, not a board analogue switch.
   With RESET_N it is a two-bit mode field. Replaced by a `Headphone Mode`
   enum; see `648c5181` in the kernel repo.

## Where the phone is

RAM-booted pmOS, card `LGV30` registered, modules staged from
`~/joan-test-assets/joan-modules.tgz` on the nest — which now contains **two
patched modules**: `snd-soc-es9218p.ko` (Headphone Mode) and
`snd-soc-wcd-mbhc.ko` (the ground-detection experiment, which failed and can
be reverted).

The module tree is **tmpfs and does not survive a reboot**. Config changes on
the SD card do survive. A backup sits beside every edited file.

## Open: MBHC, and the one lead worth starting from

Jack detection is completely dead. Measured, with a real 4-pole headset
inserted and removed many times:

* not one of the five MBHC interrupts has fired since boot;
* `MECH`/`ELECT`/`RESULT` registers are byte-identical plugged vs unplugged
  (and they are marked volatile, so those reads hit hardware);
* no input event on `event4`, no dmesg, jack kcontrols stay `off`.

Ground detection was tested and **ruled out** — see
`2026-09-11c-inline-mic-and-mbhc.md`.

**Start here instead:** the parent `wcd934x_irq` on `msmgpio 54` has fired
**exactly once, at probe**, and the SLIMbus and soundwire children on the same
interrupt controller are also at zero. The question may not be MBHC logic at
all but whether *any* WCD interrupt source reaches the SoC. If that line is
dead, every MBHC symptom follows from it and the MBHC block may be fine.

Also open, independent of detection: something clears MICBIAS2 two to three
seconds into every headset capture (`ANA_MICB2` `0x54` -> `0x14`), which would
truncate recording even once detection works.

## Bench procedure — read this before touching the rig

These cost hours this session. They are harness problems, not device problems.

* **Run session tools as `user`, never under `sudo`.** `wpctl`, `pw-cli`,
  `pactl` and `systemctl --user` need the session bus; under `sudo` they
  address an empty session and report "no sink" and blank profiles, which
  reads exactly like a broken graph. Split scripts: user for the session, root
  only for `debugfs`/regmap/`dmesg`.
* **`pkill -f <pattern>` matches the ssh command line carrying it** and kills
  its own session (exit 255). It happened five times. Kill by PID, or use a
  pattern that cannot appear in the command.
* **Detached loops die when the ssh session closes.** `setsid sh -c '...' &`
  inline does not survive; a `setsid nohup /tmp/script.sh` with the loop in a
  *file* does. Several "I heard a short tone then silence" reports were this,
  not the audio path.
* **A DPCM front-end cannot open without a backend routed.** `aplay -D hw:0,0`
  returns `EINVAL` on a freshly booted card until some `... Audio Mixer
  MultiMedia1` is on. This was misdiagnosed as a corrupted card and cost a
  reboot.
* **Rebuilding one in-tree module against the running kernel:** a dirty tree
  makes `CONFIG_LOCALVERSION_AUTO=y` stamp `-dirty` and the kernel rejects it
  (`.scmversion` does not suppress it) — pin `CONFIG_LOCALVERSION`, unset
  `_AUTO`, pass `LOCALVERSION=` explicitly, restore `.config` after. And
  `make path/to/module.ko` **truncates `modules.order` to one line**, after
  which every later `make modules` runs modpost against a module set of one;
  delete `modules.order` and `Module.symvers` to recover. Strip the result.
* **The boot script assumes it starts from LineageOS.** If the phone is in
  pmOS, `adb reboot bootloader` has no target — reboot with
  `echo b > /proc/sysrq-trigger` first.
* **`amixer` defaults to `iface=MIXER`.** The jack controls are `iface=CARD`;
  query them by `numid` or they look like they do not exist.

## Repo map correction

The live `alsa-ucm-conf-lge-joan/HiFi.conf` is the one in
**`pmaports-lg-v30-clean/device/testing/`** (9 devices, 5 capture). The copy
under `lg-v30-joan-pmos-packages/` is **stale** — deploying it wiped every
microphone device from the phone before it was restored from backup.

`pmaports-lge-joan`'s `joan/readme-build-guide` had **diverged into two
parallel lineages** — 89 ahead, 31 behind, with add/add conflicts on nine files
because the merge base predates all of them. **Reconciled 2026-09-11** at
`2eed71fddb`: merged with `-s ours` after checking that nothing existed only on
the remote side (its `CONFIG_RTC_DRV_PM8XXX=m` is `=y` here; its cmdline is a
subset of ours; its README is 307 lines against our 337 with identical
headings; Aurel's handoff doc was already present byte-identical). Aurel's 31
commits are preserved as a merge parent — nothing was force-pushed away.

`joan/audio-lpb-2026-09-11` on the fork is now redundant (its content is in
`joan/readme-build-guide`) and can be deleted whenever Lance wants.

## Commits — everything is pushed

**`linux-lg-v30-joan`** (the kernel fork)

**Branch roles matter here and are not interchangeable:** `master` is curated
**verified fixes only**; `joan/latest-clean-test` carries the **full history**.
Do not fast-forward `master` to the working tip even when git allows it —
cherry-pick verified commits instead. (Done wrong once on 2026-09-11 and
corrected; see below.)

    master                   ab54ef66  1b42626b + two verified cherry-picks
    joan/latest-clean-test   648c5181  full history
    joan/wake-path-v1        648c5181

What is on `master`, and why each earned it:

    f2b525e7  ASoC: qdsp6: q6routing: selectable capture COPP topology
              verified — None is required for capture to open at all, and
              SM_ECNS demonstrably fails the ALSA open
    ab54ef66  ASoC: es9218p: expose the mode pins and reach Low Power Bypass
              verified — LPB confirmed audible, the WCD drives the jack

Deliberately **not** promoted to `master`, though present on
`joan/latest-clean-test`:

    2f1308c2  drm/msm/dpu: gate first kickoff after wake on one TE edge
              verification status unknown to this session
    622008e1  arm64: dts: qcom: msm8998-lge-joan: micbias, ground switch, AMIC4
              only partly verified — micbias matches stock and is booted, but
              the ground-switch fix did not fix MBHC and AMIC4 is inconclusive

**Banked but deliberately NOT on a verified branch:**

    joan/mbhc-gnd-det-experiment  a54b241e  ASoC: wcd-mbhc: set gnd_det_en

That one is the ground-detection experiment. It corrects genuine dead code —
`cfg->gnd_det_en` is declared once, read once and assigned nowhere, so
`mbhc_gnd_det_ctrl()` is unreachable on every WCD codec — but it **did not fix
jack detection** and is unverified as a functional improvement anywhere. Do not
promote it on the strength of that commit alone.

`joan/master-proven-fixes` was left alone: it has diverged (50 ahead, 11
behind) and reconciling it is a separate job.

**`pmaports-lge-joan`**

    joan/readme-build-guide  2eed71fddb  <- lineages reconciled, fast-forward

**`lg-v30-port`** (docs)

    ember/pmaports-joan-gpu-publish-handoff
      523dc7c 7ac0e72 0e30ebb b76a314 270d7d9 bc1ade5 795cccc a9a119a

`.config` in the kernel tree is byte-identical to where it started, and the
kernel worktree is clean.

## Bench state at handoff

Phone is on the RAM-booted pmOS with the card registered. The module tree is
**tmpfs and does not survive a reboot** — but `~/joan-test-assets/joan-modules.tgz`
on the nest has both patched modules baked in (`snd-soc-es9218p.ko` with
`Headphone Mode`, and `snd-soc-wcd-mbhc.ko` with the failed ground-detection
experiment), so `scripts/bench-automation/nest-boot-masked-and-load-audio.sh`
restores them. Remember to load the SLIMbus modules afterwards or no card
registers, and to reboot out of pmOS first so `adb` exists for the script.

If you want a module set without the failed experiment, rebuild
`snd-soc-wcd-mbhc.ko` from `joan/latest-clean-test` and repack the tarball.
