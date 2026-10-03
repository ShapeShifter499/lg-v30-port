# joan audio defects — 2026-10-03 boot triage + fixes

Written-by: Fulgor Nymvale (agent-fulgor-zcode)
Agent-harness: ZCode:GLM-5.3-Flash
Date: 2026-10-03
Scope: kernel 7.2.0-rc2 joan line, baseline `joan/latest-clean-test` (= eeb0335090a2),
PipeWire/WirePlumber/GNOME(Phosh) on postmarketOS edge (systemd), r5 UCM
(`alsa-ucm-conf-lge-joan` at pmaports `01fd87986d`).
Fix branch: `joan/audio-fixes-2026-10-03` in worktree
`~/vibe-coding-projects/coding/linux-mainline-v30-audio-fixes`
(created off eeb0335090a2; no other worktree touched).

Fix commits:
- `7eda115e6a1c` ASoC: tfa989x: add a set_fmt op that validates the DAI wiring
- `f2b3b9424402` ASoC: qcom: sdm845: -ENOTSUPP from set_fmt is not a failure
- `0412335d91d7` ASoC: es9218p: keep regmap in cache-only while the part is in reset

All three have `Signed-off-by: Lance <Gero3977@gmail.com>` +
`Assisted-by: ZCode:GLM-5.3-Flash`. Object-build validated (see below).

---

## Symptom 1 — 50x `tert MI2S codec set_fmt failed: -524` (loudspeaker amp)

### Root cause

- `-524` is **-ENOTSUPP**, the kernel-internal errno
  (`include/linux/errno.h:27`), *not* -EPERM (-1). It is what
  `snd_soc_dai_set_fmt()` returns when the DAI driver has **no `.set_fmt`
  op at all** (`sound/soc/soc-dai.c:329-338`: `int ret = -ENOTSUPP;` only
  overwritten if `ops->set_fmt` exists).
- The tertiary MI2S backend's codec is the TFA9872 loudspeaker amp,
  bound by compatible `nxp,tfa9872` (`msm8998-lge-joan.dts:1229-1236`,
  node `speaker_amp`, wired into `tert-mi2s-dai-link` at
  `msm8998-lge-joan.dts:1787-1799`). It is driven by **tfa989x.c**, not
  tfa9879.c, and its `snd_soc_dai_ops` had only `hw_params` + `trigger`
  (`sound/soc/codecs/tfa989x.c:370-373` pre-fix) — no `set_fmt`.
- The machine driver requests `SND_SOC_DAIFMT_BC_FC | NB_NF | I2S` on the
  codec DAI in `sdm845_snd_startup()`
  (`sound/soc/qcom/sdm845.c:409-428`), gets -ENOTSUPP, and logs it at
  `sdm845.c:426` (print added by `2ff3b6eec5e8`, 2026-08-21,
  "report tertiary MI2S clock and format failures"). Control flow then
  swallows it (`ret = 0;` at the end of the case), so **playback is not
  affected** — the amp's I2S format is programmed once at probe time by
  `tfa9872_reg_init()`; the runtime format call is validation-only.

### New vs r31 baseline?

Not new. The failure has existed since the amp was wired to tert
(`2d3b27bf51d8`, 2026-08-21, "support the TFA9872, and wire joan's
loudspeaker to it"); `2ff3b6eec5e8` (same day) only made it visible. Both
commits predate r31 (FM-focused build, per
`docs/cpu-gpu-audit-2026-10-02.md`), so r31 printed the same lines; the
joan/btfm-fm-audio merge (eeb0335090a2) did not introduce or change this
path.

### Why 50x

`sdm845_snd_startup()` runs on **every frontend open** that has the
tertiary backend routed (DPCM BE startup; the verb-level route
`TERT_MI2S_RX Audio Mixer MultiMedia1 = 1` is the r5 UCM default,
`HiFi.conf` SectionVerb). PipeWire suspends idle ALSA devices after a few
seconds, so every YouTube pause/buffer/tab-switch/seek = FE close/open =
one more `set_fmt` call. WirePlumber probe cycles add more. 50 in an
evening of listening is normal churn, not a retry loop.

### Fix

- `7eda115e6a1c`: tfa989x gains a `set_fmt` that accepts exactly the
  configuration its hardware implements (clock consumer `BC_FC`, `NB_NF`,
  `I2S`) and rejects the rest with -EINVAL, like tfa9879 does. In-tree
  tfa989x users (axolotl, joan — both sdm845.c machines) request exactly
  this; msm8996-oneplus' machine (apq8096.c) never calls set_fmt, so it
  is unaffected.
- `f2b3b9424402`: sdm845.c's tert error reports now treat -ENOTSUPP as
  "nothing to configure" rather than a failure, keeping real clock/format
  errors loud (same convention the driver already applies to
  `set_channel_map` at `sdm845.c:347`).

### Choppiness (symptom 1b)

The -524 itself is swallowed and cannot cause dropouts. Ranked
candidates, all bench-checkable:

1. **Amp churn per stream start/stop.** `tfa989x_trigger()` runs
   `tfa9872_amp_start()` on every START/RESUME/PAUSE_RELEASE
   (`tfa989x.c:345-364`): up to `TFA9872_START_RETRIES = 20` rounds of
   I2C writes + 1-2 ms sleeps + status read (up to ~40 ms in the trigger
   path) waiting for SWS; STOP powers the amp down
   (`tfa9872_amp_stop()`). With PipeWire suspending the device after ~5 s
   idle, every pause/resume replays this. Watch for
   `"amplifier failed to start"` in dmesg during dropouts — that would
   mean -ETIMEDOUT, a hard stutter cause.
2. **WirePlumber device flapping** — see symptom 3; if the device drops
   and re-adds, streams re-route audibly.
3. The deliberate 130 ms/4-period IRQ-driven node settings
   (`device-lge-joan/54-joan-no-mmap.conf`) add latency but should not
   chop by themselves.

Bench A/B: play with `wpctl` open, correlate dropouts with device
object add/remove in `pw-mon`, and try `session.suspend-timeout-seconds =
0` for the ALSA monitor as a diagnostic (not a fix).

---

## Symptom 2 — 1x `es9218p 0-0048: ASoC error (-6): at snd_soc_component_update_bits() ... register: [0x00000007]`

### Root cause

- `-6` is **-ENXIO** ("no such device or address",
  `include/uapi/asm-generic/errno-base.h:10`) — the standard I2C
  address-NACK error — *not* -ENODEV (19).
- Register 0x07 = `ES9218P_FILTER_BAND_SYSTEM_MUTE`, exposed as the
  `SOC_SINGLE "Headphone Playback Switch"`
  (`sound/soc/codecs/es9218p.c:331-332`). A userspace mixer write goes
  `snd_soc_put_volsw()` (`sound/soc/soc-ops.c:354`) →
  `snd_soc_component_update_bits()` → regmap → I2C NACK →
  `soc_component_ret_reg_rw()` prints "ASoC error (-6): at
  snd_soc_component_update_bits() ..." (message helper
  `sound/soc/soc-utils.c:38`).
- Since `d00fb16818b7` (2026-09-27, "idle in Low Power Bypass so the WCD
  can see the jack") the driver parks the ES9218P with **RESET_N
  asserted** at probe end and after every stream close
  (`es9218p_amp_power_down()` → `gpiod ... reset_gpio, 1`,
  `es9218p.c:543-545`). A part in reset does not answer on I2C, so any
  mixer access made while the DAC is idled NACKs. This commit was
  "untested" on the bench until this boot
  (`docs/hardware-gap-sweep-2026-10-02.md` row 22) — the correlation is
  exact: jack detection now works, and the first idle-time mixer write
  (WirePlumber restoring card state, or the UCM HeadphonesHiFi
  `EnableSequence` cset `name='Headphone Playback Switch' on`) produced
  exactly one -ENXIO.

### Fix

`0412335d91d7`: put the regmap in **cache-only** whenever RESET_N is
asserted (probe end, `amp_power_down`, `mode_put` into reset modes) and
out of it when the part wakes (`amp_power_up`, `mode_put` back to
HiFi/LoFi), ending `amp_power_up()` with a `regcache_sync()` so values
written while idle (desktop volume, mute) reach hardware on the next
power-up. Userspace now sees success for idle-time writes; the chip gets
them when it comes alive. The one behaviour change: with the part parked,
`hw_params`' INPUT_SELECT write is cached instead of erroring — the
mode_put DAPM pin handling already prevents streams from opening in
non-HiFi modes.

---

## Symptom 3 — GNOME Settings Sound panel: no output devices (Phosh pulldown lists them)

### Enumeration chain

- Kernel card: name/long-name **"LG-V30"**, driver **"sdm845"**
  (`msm8998-lge-joan.dts:1717` model; `sdm845.c:21,609` DRIVER_NAME) —
  matches the shipped UCM entry point
  `ucm2/conf.d/sdm845/LG-V30.conf` (APKBUILD installs to
  `/usr/share/alsa/ucm2/conf.d/sdm845/LG-V30.conf`), which pulls verb
  `Qualcomm/sdm845-lge-joan/HiFi.conf`: SectionVerb (TERT route + mic
  route) + devices Speaker, Earpiece, Headphones (WCD LPB),
  HeadphonesHiFi (ES9218P), Mic, Headset, DualMic, Camcorder{,Rotated}.
- WirePlumber's ALSA monitor (UCM mode) creates the PipeWire device +
  per-UCM-device nodes; `pipewire-pulse` exports them as PulseAudio
  sinks; **both** GNOME Settings (g-c-c's bundled libgnome-volume-control)
  and Phosh's quick settings read the same PulseAudio socket — the panel
  lists sink *ports/devices*, so if no sink got exported, the panel is
  empty while PipeWire-side *device objects* (what the pulldown shows)
  still exist.

### What the evidence supports

The UCM **file itself is not the defect**: card/driver names match, the
verb routes a backend at enable time (the fix from r5, `01fd87986d`),
and the loudspeaker works through it. The two runtime failure sources
found:

1. **Pre-fix kernels poison the HeadphonesHiFi device** — its
   EnableSequence writes the ES9218P "Headphone Playback
   Switch"/"Volume" (dead I2C while idle-in-LPB, symptom 2); a cset
   failure aborts the device enable, and WirePlumber's own state restore
   of that switch NACKs at boot. Symptom 2 is the visible fingerprint.
2. **Boot-time profile-activation race** — the profile activates while
   slim-ngd is still negotiating QMI (symptom 4 fires at ~12 s); a
   failed/deferred activation leaves the card in "Off", no sinks are
   exported, and WirePlumber does not always re-scan later (a known
   class of bug — restarting WirePlumber refreshes the device list, see
   [Red Hat Bugzilla](https://bugzilla.redhat.com) reports on
   wireplumber device enumeration, and the standard
   "Dummy Output / corrupt state" remediations of clearing
   `~/.local/state/wireplumber`).

Both are covered/clarified by the kernel fixes + bench steps below. No
functional UCM change is required; one **optional hardening diff** is
staged (park the DAC back in LPB when the HeadphonesHiFi output is
deselected, mirroring the kernel's stream-close idle so MBHC jack
detection resumes):

```diff
--- a/device/testing/alsa-ucm-conf-lge-joan/HiFi.conf
+++ b/device/testing/alsa-ucm-conf-lge-joan/HiFi.conf
@@ -238,10 +238,18 @@
 	DisableSequence [
 		cset "name='Headphone Playback Switch' off"
+
+		# Park the ES9218P back in Low Power Bypass, the same idle the
+		# kernel drives on stream close (d00fb16818b7): RESET_N drops,
+		# the jack returns to the WCD9340, and its MBHC detection sees
+		# insertions again once this output is deselected.  Keep this
+		# after the Switch write: a part in reset NACKs I2C, so on
+		# kernels before the 2026-10-03 cache-only fix a leading Mode
+		# cset would kill every write after it.
+		cset "name='Headphone Mode' Low Power Bypass"
+
 		cset "name='QUAT_MI2S_RX Audio Mixer MultiMedia1' 0"
 		cset "name='TERT_MI2S_RX Audio Mixer MultiMedia1' 1"
 	]
```

(Do NOT apply to `pmaports-lg-v30-clean` — that tree has another owner.
If adopted, refresh `sha512sums` in the APKBUILD and bump pkgrel.)

---

## Symptom 4 — `qcom,slim-ngd-ctrl 171c0000.slim-ngd: QMI wait timeout` (1x, ~12 s)

Noted, not fixed: single-shot boot-time QMI service negotiation timeout
while the audio QMI client comes up; WCD9340 audio works afterwards
("likely benign" — consistent with a late remoteproc/pd-mapper service
at first bring-up). Its only relevance here is timing: it lands exactly
where WirePlumber first activates the UCM profile (symptom 3, race
candidate). If it repeats per-boot and jack/profile activation is flaky,
making the audio QMI service ready earlier is the lever — not the slim
driver.

---

## Validation (object builds, done)

```
worktree: ~/vibe-coding-projects/coding/linux-mainline-v30-audio-fixes @ joan/audio-fixes-2026-10-03
make -C ~/vibe-coding-projects/coding/linux-mainline-v30-audio-fixes \
    ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=$HOME/kernel-builds/audio-check -j4 \
    sound/soc/qcom/sdm845.o sound/soc/codecs/tfa989x.o sound/soc/codecs/es9218p.o
```
Clean; objects at `~/kernel-builds/audio-check/sound/soc/{qcom/sdm845.o,codecs/tfa989x.o,codecs/es9218p.o}`
(config from `~/kernel-builds/btfm-check/.config` with
`CONFIG_SND_SOC_TFA989X=m` + `CONFIG_SND_SOC_ES9218P=m` added;
`olddefconfig` settled).

## Bench steps for Lance

1. Build/deploy the full kernel from `joan/audio-fixes-2026-10-03`
   (object-only validation here; no phone access this pass).
2. Boot, then:
   - `dmesg | grep -E "set_fmt|ASoC error"` → expect **zero** lines
     (was: 50x -524, 1x -6).
   - `amixer -c0 cset name='Headphone Playback Switch' on` while nothing
     plays, then `off` → expect success both times (cache-only path);
     plug headphones → jack detect should still fire (LPB idle
     preserved).
   - `wpctl status` → card LG-V30 with profile **HiFi** active; sinks
     `...HiFi__Speaker` (default), `...HiFi__HeadphonesHiFi` etc.
   - GNOME Settings → Sound: **Speaker** (and Headphones entries) listed;
     Test speaker + headphones by ear (Speaker via TFA9872,
     HeadphonesHiFi via the ES9218P — the volume slider should now drive
     real DAC attenuation, including values set while idle).
3. If the panel is still empty on a healthy dmesg: `systemctl --user
   restart wireplumber pipewire-pulse` → if devices appear, it is the
   boot-time activation race (symptom 3, item 2) — grab
   `journalctl --user -u wireplumber -b` around the ~12 s mark and we fix
   it with a boot-order/retry change, not a UCM change. Also try
   `rm -rf ~/.local/state/wireplumber` once (stale restore state) before
   concluding.
4. Choppiness: with dmesg clean, listen again; if stutter remains,
   `pw-mon` while playing (device flapping?) and check for
   `amplifier failed to start` (amp_start timeout) — next suspects are
   the trigger-path retry loop and device suspend, not the set_fmt path.
5. If adopting the UCM diff: rebuild `alsa-ucm-conf-lge-joan`, bump
   pkgrel, and verify `alsaucm -c LG-V30 list _devices/` still shows the
   full set after a HeadphonesHiFi disable.
