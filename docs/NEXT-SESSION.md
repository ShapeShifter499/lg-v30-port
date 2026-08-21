# LG V30 (joan) — next session start here

**2026-08-21f (Ember) — UCM profile written + validated; new pmOS package repo.**
- **New repo (local, unpushed):** `~/vibe-coding-projects/coding/joan-pmos-packages`
  — suggested name `lg-v30-pmos-packages` to match `lg-v30-port`. Subdirs:
  `alsa-ucm-conf-lge-joan/` (new) and `firmware-lge-joan/` (COPIED; the
  standalone repo is untouched — Lance plans to retire it).
- **Why audio needs a UCM package:** kernel audio works, but PipeWire will not
  expose a card with no UCM profile → pmOS Settings shows "dummy output" and
  `wpctl status` lists ZERO audio devices.
- **Profile validated with alsaucm on hardware:**
  `0: Headphones — Headphone jack (ES9218P Quad DAC)`; enabling it sets
  `QUAT_MI2S_RX Audio Mixer MultiMedia1 = on` and
  `Headphone Playback Volume = 195` (~-30 dB; 255 = 0 dB is painfully loud).
- **UCM GOTCHAS (cost real time):**
  1. **Matching is on the card LONG NAME (`LG-V30`), not the id (`LGV30`).**
     `alsaucm -c 0` and `-c LG-V30` work; `-c LGV30` always fails with -2.
     I misread that as a broken profile; bisected by pointing our conf.d entry
     at the SHIPPED db845c config — it failed identically, proving the lookup
     not the content was at fault.
  2. Shipped sdm845 profiles use **`Syntax 3`** and bare control names
     (`PlaybackVolume "Headphone Playback Volume"`), not Syntax 6 / `name='...'`.
  3. Layout: `conf.d/<card driver>/<long name>.conf` → `Qualcomm/<board>/HiFi.conf`.
- **CONFIRMED WORKING END-TO-END:** the sink shows in pmOS Settings and its
  built-in audio test plays. My earlier "not working" call was a measurement
  error — `wpctl` over plain ssh is not attached to the phosh session's
  PipeWire, so it reported zero devices. Read the session bus from
  `/proc/$(pgrep -x wireplumber)/environ` before trusting any session query.
- (superseded) previously recorded as unproven through PipeWire: This rootfs is **Alpine/OpenRC
  — there is no `systemctl`**, so every "restart wireplumber" I tried was a
  silent no-op (PID never changed). Needs one boot with the package installed.
- **BLOCKED ON A DECISION: `master` diverged.** 11 commits exist only on
  `master` (6fc576542), 22 only on HEAD. Force-pushing HEAD there would discard
  those 11, and HEAD carries the full debug stack (28 JOAN-* hooks) while master
  is meant to be proven fixes. `joan/latest-clean-test` is current at 50ed1c09e.


**2026-08-21e (Ember) — *** WORKING STEREO AUDIO ON JOAN *** through the ES9218P Quad DAC.**
Kernel `ghfork/joan/latest-clean-test` `50ed1c09e`.
- **Working chain:** aplay → q6asm → ADM → AFE **QUATERNARY** MI2S → gpio58/59/61
  → **ES9218P** (our reverse-engineered driver) → headphone jack. Both channels
  clean, correct left/right orientation (verified with a spoken channel clip),
  real-time playback.
- **Two bugs fixed this session, both mine, both one-liners in effect:**
  1. **Wrong port.** The DAC is on QUATERNARY MI2S, not tertiary. I inferred
     tertiary from downstream's `dai_mi2s2` having SD1 as an output instead of
     reading the dai-link that NAMES the codec (`LPASS_BE_QUAT_MI2S_RX` /
     `msm-dai-q6-mi2s.3` → `es9218-codec.1-0048`, under `CONFIG_SND_USE_QUAT_MI2S`
     which every joan defconfig sets). Cost ~4 boots + a tertiary implementation
     joan does not use.
  2. **Wrong register field.** Serial word length is **bit 7** of the input-select
     register and LG writes the WHOLE byte (0x00 = 16-bit, 0x80 = 24/32-bit). We
     were writing bits 1:0, so the register kept its 0x8c reset value = 32-bit
     while 16-bit frames arrived. That single field caused BOTH the crackle
     (frame misalignment) and the underruns (6 s file returning in 2-3 s).
- **Decisive instruments, use these first next time:**
  - DAC `DPLL_NUMBER` regs **0x42-0x45**, read WHILE PLAYING. `0x00000000` = no
    input clock at all (wrong port / dead clock); non-zero = locked. This would
    have caught the wrong port in one boot.
  - **Play duration vs file duration.** A 6 s file returning in 2-3 s is underrun,
    not a routing fault. Cheap, needs no instrumentation.
- **Volume safety:** control 255 on `Headphone Playback Volume` is 0 dB on a
  headphone amp and was painfully loud. Keep test sweeps at or below ~210.
- Still open / next: cap a sane default volume in the driver; wire the ES9218P
  properly into DAPM/jack detection; the WCD9340 analog outs remain unused on
  this board; loudspeaker (TFA9872 on quaternary TDM / i2c_7) is untouched and
  needs its firmware container loaded from joan's own partition.
- Tooling: `docs/tools/` has gpiohold.c and the codec setup recipe. Channel-test
  and tone clips were generated locally with espeak-ng (installed on skyforge
  this session).


**2026-08-21d (Ember) — AFE I2S payload diffed against downstream: composition logic is CORRECT by inspection. Runtime capture still owed.**
Kernel `58d3cb4eb`.
- **`set_sysclk` is NOT silently failing.** Added error logging (`2ff3b6eec`);
  `snd_soc_dai_set_sysclk(TER_MI2S_IBIT, 1536000)` and both `set_fmt` calls all
  return **0**, and the ADSP acks `AFE_SVC_CMD_SET_PARAM` (0x100f3) and
  `AFE_PORT_CMD_DEVICE_START` (0x100e5). That theory is dead.
- **Payload diff, by source inspection — every field checks out:**
  - `ws_src`: derived from the DAI fmt at `q6afe.c:1526`. `SND_SOC_DAIFMT_BP_FP`
    → `WS_SRC_INTERNAL` (LPASS drives the clocks). The machine driver passes
    `BP_FP` for the cpu_dai, so this is right. **This was the prime suspect —
    EXTERNAL would have explained the dead clock exactly — and it is not it.**
  - `sd_line_mask`: `qcom,sd-lines = <1>` → `priv->sd_line_mask |= BIT(1)` →
    `AFE_PORT_I2S_SD1`. Correct for joan (downstream `rx-lines = 2`, same line).
  - `q6i2s_ops` (which carries `set_fmt`/`set_sysclk`) IS assigned to tertiary:
    `q6dsp-lpass-ports.c:713`, range `PRIMARY_MI2S_RX ... QUATERNARY_MI2S_TX`.
  - prepare dispatch covers tertiary too (`q6afe-dai.c:417`), calling
    `q6afe_i2s_port_prepare()`.
- **STILL OWED: the runtime values.** `58d3cb4eb` adds a `JOAN-I2S` dump of the
  composed payload, but it never fired in the sampling windows I tried —
  `q6afe_i2s_port_prepare()` was not entered during my manual plays, most likely
  because the detached tone loop already had the BE up and a second FE open
  reuses it rather than re-preparing. **Next session: boot, do ONE aplay with no
  loop running, and read the `JOAN-I2S` line.** That gives the actual
  ws_src/channel_mode/rate on the wire.
- Unchanged from 2026-08-21c: the DAC is alive (chip id 0xd0), LG's init and the
  analog amp power-up are ported and byte-exact, and `DPLL_NUMBER` reads
  **0x00000000** while playing — the DAC sees no input clock. Everything from
  the routing through to the amplifier is exonerated.
- Remaining candidates, now that the payload logic is cleared: LPASS not
  physically driving the pads despite the ack; an msm8998-specific LPASS clock
  root/gating difference; or a hardware-level check (scope gpio75/76) to settle
  whether BCLK/WS toggle at all.


**2026-08-21c (Ember) — ES9218P Quad DAC ALIVE and fully configured; DPLL sees NO input clock. That is the whole remaining problem.**
Kernel `ghfork/joan/latest-clean-test` `d21c5513f`.
- **DAC probes on real silicon:** `es9218p 0-0048: ES9218P chip id 0xd0` — the exact
  value LG's driver checks for (`es9218p.c:2758`). Our reverse-engineered driver's
  regmap, I2C addressing and power sequencing are correct.
- **LG's init + analog amplifier power-up are ported** (`d21c5513f`) and verified
  **byte-exact against LG's own inline comments**, read off the chip during playback:
  `ANALOG_OVERRIDE 0x7c`, `CP_OVERRIDE 0x78`, `AMP_CONFIG 0x02` (HiFi1),
  `DIGITAL_OVERRIDE 0x03`, `HPA_CTRL 0x47` (ENHPA_OUT set), analog volume restored —
  and torn back down between streams by the DAPM event.
- **STILL SILENT, and the cause is now located:** with a tone playing,
  **`DPLL_NUMBER` (0x42-0x45) reads 0x00000000**. The DAC's DPLL has nothing to lock
  to — it sees **no input clock**. Everything downstream of the clock (amp, registers,
  volume, routing) is therefore exonerated; do not re-audit it.
- **SoC side looks correct on paper:** `q6afe_dai_prepare dai id 20`,
  `AFE_PORT_CMD_DEVICE_START` (token 0x14) issued **and acked**; pins report
  `device sound function ter_mi2s` on gpio75/76/78; `TERT_MI2S_RX Audio Mixer
  MultiMedia1` routes. But an ADSP ack means the command was accepted, **not** that
  LPASS is physically toggling the pins.
- **MCLK is probably NOT the issue:** LG's es9218p.c never calls `clk_get`/
  `clk_prepare`, and joan's DAC node has no `clocks` property — so the part almost
  certainly has a dedicated on-board oscillator. Worth confirming, but it means the
  suspect is the I2S clock/data from LPASS, not a missing MCLK.
- **NEXT: prove whether BCLK/WS are actually toggling on gpio75/76.** Options, cheapest
  first: (a) check LPASS/q6afe clock state and whether
  `Q6AFE_LPASS_CLK_ID_TER_MI2S_IBIT` really enables — the machine driver ignores
  `snd_soc_dai_set_sysclk`'s return; (b) compare the AFE MI2S port config payload
  against downstream's; (c) scope gpio75/76 if hardware access is easy.
  Also verify `qcom,sd-lines = <1>` is the right encoding for SD1 in mainline q6afe
  (downstream expresses it as a bitmask, `rx-lines = 2`).
- Tooling: nest `~/joan-images/staging/qmidbg29a/`. Image
  boot-joan-qmidbg29a.img (c2aa0603..., size **30003200** — the kernel grew, so pass
  the size explicitly to boot scripts).
- **Rig trap hit three times this session:** `pkill -f <pattern>` inside a
  `sudo sh -c '...'` whose own command line contains that pattern kills its own shell.
  Use a bracket pattern (`"joan-liste[n]"`) or drop the pkill.
- **Read DAPM state and DAC registers only WHILE A TONE IS PLAYING.** Sampling between
  plays shows the power-down state and looks exactly like a failed sequence — that
  cost a wrong diagnosis this session before the second read corrected it.


**2026-08-21b (Ember) — codec DAPM lane opened. Chain proven ON end to end; still not audible; topology question is the blocker.**
Handoff: `docs/ember-handoff-2026-08-21-audio-crash-fixed-dapm-open.md`.
Kernel `ghfork/joan/latest-clean-test` `2fac70c23`.
- **START HERE: the corrected-gain configuration has never been listened to.**
  Run `docs/tools/joan-codec-dapm-setup.sh` + `docs/tools/tone-440L-660R-6s.wav`
  and listen. It may simply work.
- **My gain bug, do not repeat:** `SOC_SINGLE_S8_TLV("RXn Digital Volume",
  …, -84, 40, …)` — the control value is an OFFSET FROM -84 dB. `0` = -84 dB =
  silence; **84 = 0 dB**. A whole listening pass was spent at -84 dB.
- **Stereo FIXED:** setting `SLIM RX1 MUX` = AIF1_PB as well as RX0 takes the
  AFE port from `ch 1 map 144` to `ch 2 map 144/145`.
- **Measured working (not assumed):** with a tone playing, the whole codec DAPM
  chain reads On from `AIF1 PB` through `HPHL PA` to `HPHL`; `ANA_HPH`=0xf0
  (both PAs + both DACs), `ANA_EAR`=0xa0, `ANA_RX_SUPPLIES`=0xc1,
  `RX0/RX1_RX_PATH_CTL`=0x24 (enabled, unmuted, 48 kHz). SLIMbus stream really
  is established (CONNECT_SINK, DEF_ACT_CHAN, RECONFIG_NOW, no bus errors).
  Everything the codec can do, it is doing.
- **The open question is topological:** joan may not connect the WCD9340's
  analog outputs to any transducer. Headphone goes via **ES9218P** (i2c_1 0x48,
  fed by tertiary MI2S); loudspeaker via **TFA98xx** (i2c_7 0x34, quaternary
  MI2S); and downstream's `qcom,audio-routing` for joan lists **only mic
  paths**. Settle this with a teardown photo / service manual / stock
  `mixer_paths_*.xml` before writing more code.
- **ES9218P Low Power Bypass** (WCD analog → jack): power `&pm8998_gpios 10`
  HIGH, hifi_mode2 `&pm8998_gpios 12` HIGH, reset `&pmi8998_gpios 2` LOW.
  PMIC DT numbering is 1-based and matches downstream (`of_xlate` subtracts
  `PMIC_GPIO_PHYSICAL_OFFSET`).
- **OPEN BUG: the DT gpio-hogs silently do nothing.** Nodes are in the live DT;
  the pins stay inputs; nothing logged. Use `docs/tools/gpiohold.c` (static
  aarch64, GPIO_CDEV) until fixed — the phone has no GPIO_SYSFS and no libgpiod.
- **Workflow win:** boot 24a survived the whole session, so the codec was poked
  live over ssh with no reboots. Dump DAPM **while playing** — an idle dump
  shows everything Off and proves nothing. Widgets:
  `/sys/kernel/debug/asoc/LG-V30/wcd934x-codec.0.auto/dapm/`; codec regmap:
  `/sys/kernel/debug/regmap/217:250:1:0/registers`; `mount -t debugfs none
  /sys/kernel/debug` first.
- **ES9218P driver** (`dbd7d8f4d`) is OUR reverse-engineered port, Lance-approved
  and a deliverable — it is NOT in mainline. Never probed;
  `CONFIG_SND_SOC_ES9218P` not enabled. It is the proper home for the mode pins.


**2026-08-21 (Ember) — AUDIO CRASH FIXED. Root cause: q6asmdai had no `iommus`, so the DSP was given an unmapped physical address. PCM playback now runs end to end.**
- Boots 21a/21b/22a/23a. Root-cause + fix evidence:
  docs/evidence/2026-08-21-runtime-pm/boot-22a-23a-adsp-smmu-root-cause-and-fix.md
- **THE FIX** (kernel `ab99261d5`): `q6asmdai { iommus = <&lpass_q6_smmu 1>; }`
  in msm8998.dtsi + `&lpass_q6_smmu { status = "okay"; }` in the joan DTS.
  `q6asm_dai_probe()` reads `iommus` to recover the audio SID and puts it in
  bits [63:32] of the buffer address it hands the DSP (`q6asm-dai.c:452`).
  Without it `sid = -1`, the buffer is allocated against a device attached to
  no IOMMU, and the DSP gets a bare physical address. The mem-map command
  still succeeds (the ADSP only records the address); the fault lands on the
  first `ASM_DATA_CMD_WRITE_V2`, and a Q6 translation fault on msm8998 is a
  silent SoC reset handled below the kernel. SID 1 is confirmed twice:
  sdm845 `apps_smmu 0x1821` (& 0xF == 1) and downstream `msm-audio.dtsi:448`
  `qcom,msm-audio-ion iommus = <&lpass_q6_smmu 1>`.
- **Boot 23a result:** `aplay1 rc=0`, `aplay2 rc=0`, phone alive to the end.
  156 `ASM_DATA_EVENT_WRITE_DONE_V2`, 2 `ASM_SESSION_CMD_RUN_V2`, six wall
  seconds per five-second clip (real time, so the port clocks at 48 kHz),
  clean `SHARED_MEM_UNMAP` + `ADM_CMD_DEVICE_CLOSE_V5` teardown. That also
  retires the separate teardown-crash suspect open since 2026-08-17.
- **NOT yet audible.** aplay fed /dev/zero. The analog path is still open:
  the AFE port is configured for ONE channel (`ch 1 map 144/0/0/0`, only
  `SLIM RX0 MUX` routed — stereo needs RX1); joan's DT has no
  `audio-routing`; the codec logs many `ASoC: mux ... has no paths`
  (RX INT0-7 MIX2 INP, CDC_IF TX9/10/11/13); and the codec chain
  (RX INT0_1 MIX1 INP0 = RX0, RX INT0 DEM MUX = CLSH_DSM_OUT, SPK PA) has
  never been set up. **Next lane is codec/DAPM, not SLIMbus or ADSP.**
- How it was found: an `apr.apr_hb_ms` heartbeat (kernel `6fd85e81c`) showed
  that the log "ending" at the seventh APR response was really 320 ms of
  nothing printing while aplay filled its buffer — 18 heartbeats run through
  that gap. `apr.apr_dbg` then named every command. Both default off.
- Retired along the way, all with evidence: downstream SPS/BAM pipe setup
  (rejected from source — downstream gates it on `wbuf[0] == dev->pgdla` and
  our connects target the codec); `joan_pipe_bringup`; and the whole of
  runtime PM (boots 21a/21b pinned the bus awake and it died identically).
  None of them were ever in the data path.
- **Rig: netconsole had never worked** — `netpoll: netconsole: usb0 doesn't
  exist, aborting` at 3.05 s, the cmdline initcall runs long before the USB
  gadget. Configure it via configfs after usb0 is up, with nest's live MAC
  (randomised every boot), and positive-control it through `/dev/kmsg`
  before spending a run. Recipe in the 21b evidence doc.
- Also fixed in the rig: wait for `sys.boot_completed` before `dumpsys
  battery`; if the phone is left in pmOS, reboot it to Android first
  (fastboot is only reachable from there).
- Tooling: nest `~/joan-images/staging/qmidbg2{1a,2a,3a}/`. Working image
  **boot-joan-qmidbg23a.img** (sha256 14191725865477df01c56f21ce42f3590a7bfd13839ae5f41a32bcc751733d33).


**2026-08-21 (Ember) — runtime PM RETIRED; SPS/BAM lead rejected from source; netconsole was dead all along and is now live.**
- Boots 21a + 21b (evidence: docs/evidence/2026-08-21-runtime-pm/, analysis:
  docs/ember-2026-08-21-audio-runtime-pm-and-sps-deadend.md).
- **Lead #1 (port downstream's SPS/BAM pipe setup) is REJECTED from source.**
  Downstream runs `msm_slim_connect_pipe_port()` only when the connect targets
  the APPS PGD (`slim-msm-ngd.c:658`, `wbuf[0] == dev->pgdla`, and `wbuf[0]` is
  `txn->la` at `:577`). Our connects target the codec (0xcf/0xce), so downstream
  does no SPS/BAM setup on this path either. The apps BAM data pipes are not in
  the audio path at all — data is ADSP<->codec, the apps NGD is control-only.
  Same reasoning retires `joan_pipe_bringup`; run with `joan_pipes=0`.
- **Runtime PM is RETIRED as the killer**, this time on real evidence. The
  earlier ruling-out was invalid: the sysfs check read the PARENT device
  (`171c0000.slim-ngd`), which never calls `pm_runtime_use_autosuspend()`, so
  `-EIO` was the expected answer and every raise to 5000 ms wrote nothing. The
  live node is the child pdev `qcom,slim-ngd.1`. With
  `slim_qcom_ngd_ctrl.autosuspend_ms=600000` the bus stayed `active` across the
  whole run — four `JOAN-PM` breadcrumbs in 12677 lines, all from the initial
  DOWN->AWAKE resume, zero suspends, zero `exit_dma` — **and it died anyway, in
  the same place.** So the 100 ms autosuspend, the `exit_dma()` -> `BAM_P_RST`
  teardown of the ADSP-owned BAM, and the QMI power-down vote all go.
- **netconsole had never worked.** Not the MAC: `netpoll: netconsole: usb0
  doesn't exist, aborting` at 3.05 s — the cmdline initcall runs long before the
  USB gadget. Its silence carried no information on any prior boot. Fixed by
  configuring it via configfs at runtime with nest's live MAC (pmOS randomises
  the CDC host MAC every boot), and the run now positive-controls the channel
  through `/dev/kmsg` before spending the audio sequence. Recipe in the 21b doc.
- **Where it dies, now measured by two independent channels that agree
  exactly:** 32 ms after `slim port 16384 cfg`, on the seventh `apr_audio_svc`
  response. The apps kernel acks it (`rx_done sent liid 7`) and then emits
  nothing — no fault, no warning, no panic — through a synchronous, unbuffered
  channel. Remaining space: the ADSP faulting on the AFE port start (hardware
  watchdog; the remoteproc "crash detected in adsp" path never fires), or an
  apps-side MMIO wedge we have not identified.
- **Two new leads from the log:** (a) the AFE slim port is configured for ONE
  channel on a stereo stream (`ch 1 map 144/0/0/0`) — only `SLIM RX0 MUX` is
  routed, so stereo needs RX1 too; (b) wcd934x prepares and enables its slim
  stream from the DAI **trigger**, not `.prepare`, so the ADSP is told to start
  the AFE SLIMbus port before the codec has defined or activated the channel it
  is meant to drive. Ordering is now a first-class suspect.
- **Next (one rebuild, one boot):** log the APR packet header (opcode, svc,
  token) on rx so we know *which* command's response is the seventh, plus a
  20 ms param-gated heartbeat to settle whether the apps CPU outlives the ADSP.
- Tooling: nest `~/joan-images/staging/qmidbg21a/` — repack-qmidbg21{a,b}.sh,
  boot-test-21{a,b}.sh, joan-audio-seq.sh, reboot-readback-21a.sh. Images
  boot-joan-qmidbg21a.img (e1b27b83...) and 21b (46665c21...).
- Rig gotchas added: the boot-test must wait for `sys.boot_completed` before
  `dumpsys battery`; and if the phone is left in pmOS, reboot it to Android
  before a new run (fastboot is only reachable from there).


**2026-08-18 (Aurel, eighth shift) — PGD laddr discovered (0xc4); pipe connects clean; ADSP wedge persists ~0.2s after stream setup.**
- Boots 20e r3/r4, 20f, 20g, 20h (evidence: docs/evidence/
  2026-08-18-persistent-log/boot-20e-to-20h-pgdla-and-qmi-gap.md).
- PGD discovery FIXED: call ctrl->get_laddr() directly (downstream-style);
  slim_get_logical_addr() short-circuits on the cached laddr and the
  result-code-vs-address bug sent connects to LA 0. ADSP answers
  pgdla = 0xc4; all 12 USR pipe connects post with ZERO bus errors.
- Bring-up now fires on bus RE-activation (runtime_resume, prev_state !=
  DOWN) via the ngd_master workqueue (direct call would deadlock under
  RPM_RESUMING). The wake power_up takes the NGD_STATUS LADDR early-return
  path — hooks at the reconf-wait tail are unreachable.
- Death persists: silent SoC reset ~1.3 s after stream setup (AFE port
  cfg + codec IFC writes), racing ahead of the PCM trigger. Autosuspend
  is NOT the cause (r4 died without a suspend cycle; the sysfs
  autosuspend_delay_ms file errors EIO on this device anyway).
- Top leads: unanswered ADSP QMI indication (IPCRTR len 48) at stream
  setup; codec-side SLIM PGD port int enables (wcd934x enable_slim);
  downstream's SPS/BAM pipe setup (msm_slim_connect_pipe_port) that
  mainline lacks; ADSP ramdump unreachable (silent hw reset).
- Evidence rig (works): SD root mount -o sync + INCREMENTAL dmesg -c
  logger + detached setsid seq script. ssh -tt WITHOUT -n when piping
  the sudo password ( -n eats stdin -> sudo hangs ).
- Images on nest: boot-joan-qmidbg20h.img (7545489b...) latest; staging
  ~/joan-images/staging/qmidbg20h/ with repack + boot-test + seq scripts.

**2026-08-18 (Aurel, seventh shift) — PGD-write kill PROVEN and removed; stream links; crash persists at trigger (20e evidence in flight).**
- Boot 20c/20d used the PHONE-SIDE persistent SD-root dmesg logger (sync-per-
  line). Evidence: docs/evidence/2026-08-18-persistent-log/.
- Boot 20d dump_stack proved the kill chain: aplay trigger ->
  slim_stream_prepare (first USR CONNECT) -> joan pipe bring-up ->
  ADDR_QUERY (fine) -> FIRST app-side writel to PGD_PORT_CFGn (0x14000)
  HANGS the CPU while the ADSP's audio machinery is live. Silent, no panic,
  SoC reset to Android. ADSP owns the PGD block; app-side PGD register
  writes are RETIRED for good (also explains Boots R/S/T).
- Boot 20e (f173f0394): removed the PGD writes; keep pgdla discovery +
  USR CONNECT_SRC/SINK posts. The stream now LINKS (mixer set => BE found;
  q6slim_hw_params + q6afe_dai_prepare fire) — the "no backend DAEs" error
  is only daemon-opens-before-mixer ordering, NOT a topology bug.
- 20e still dies during aplay1 (no "aplay1 rc=" in joan-mixer2.txt);
  first two 20e evidence pulls were eaten by ext4 journal rollback after
  the crash. 20e-r3 uses mount -o sync + INCREMENTAL dmesg -c logger
  (full-buffer dumps were too slow to reach the crash point).
- Fixed recipe for phone-side evidence: remount,rw,sync; rm logs; detached
  seq script (setsid) + dmesg -c loop to /var/log/joan-aplay.log.
- Tooling: nest ~/joan-images/staging/qmidbg20e/{repack-qmidbg20e.sh,
  boot-test-20e.sh, joan-audio-seq.sh}; image boot-joan-qmidbg20e.img
  (sha256 93f755d2d0055d2688d16cded2033673fd16b549d8958729a9d652106a349726).
- Next: analyze 20e-r3 crash point; likely walls after the PGD fix: the
  USR pipe-connect handling on the ADSP side (connect w/o app-side port
  programming), or the ADSP watchdog on the same stream path.

**2026-08-18 (Aurel, sixth shift) — Boot X ran: core blocks hang on READ; controller is V2 NGD; pivot to message path.**
- Boot X (qmidbg19x, STRICT_DEVMEM=n, pgd_enable=0): userspace read-probe before
  ADSP start. 0x171c0004 (COMP_CFG_V2) reads OK = 0x0; 0x171c0200 (MGR_CFG)
  read wedges the system permanently (SIGKILL can't recover; USB died; no
  netconsole output). Control run: garbage unmapped reads hang cores only
  transiently (recover after SIGKILL) => the 0x200 wedge is register-specific.
- Downstream register map (android_kernel_lge_msm8998/drivers/slimbus/slim-msm.h):
  V1 vs V2 offset layouts via CFG_PORT(). All observed behaviors match V2
  (COMP_CFG=4, TRUST=0x3000, PGD_CFG=0x800, OWN=0x300C, PGD_PORT_CFGn=0x14000).
- The component-init sequence (Boots R-W) came from slim-msm-ctrl.c — the
  NON-NGD manager driver. msm8998.dtsi binds qcom,slim-ngd for slim@171c0000,
  and downstream slim-msm-ngd.c never writes COMP_CFG/MGR_CFG. The core is
  ADSP-owned; app-CPU MMIO to 0x200+ hangs BY DESIGN. Boots R-W direction REJECTED.
- NEXT (Boot Y/Z): code study DONE — mainline never reads the ADSP's QMI
  requests (svc 0x0301 rx side missing; downstream drains them and programs
  pipe ports on request). Port downstream's QMI recv path (kworker +
  QMI_RECV_MSG + rx handlers) + pipe-port connect (PGD_PORT_CFGn/BLKn/TRANn,
  port_b rewrite, pgdla get_laddr) into qcom-ngd-ctrl.c. Reconfigure-range
  drop is CORRECT NGD behavior — reconf_passthrough retired as dead end.
  See docs/evidence/2026-08-17-qmi-boots/boot-Y-codestudy-qmi-rx-gap.md.
- Evidence: docs/evidence/2026-08-17-qmi-boots/boot-X-readprobe.md.
- Tooling staged on nest: ~/joan-images/staging/qmidbg19x/{devprobe,probe-x.sh,
  nest-bootx.sh,repack-qmidbg19x.sh}; image boot-joan-qmidbg19x.img
  (sha256 f2fd7f28...).

**2026-08-17 night (Aurel, fourth shift) — PGD writes HANG; next: downstream init-sequence port.**
Boots Q/R/S/T mapped the CONNECT_SINK wall to the missing PGD programming:
- Q: port-level PGD_PORT_CFGn writes are IGNORED (cfg reads back 0); connect
  stalls; ADSP watchdogs 1.3s later ("crash detected in adsp: type watchdog") = the kill.
- R/S/T: the PGD_CFG (0x800) + PGD_OWN_EEn (0x300C+4*ee, 0x3F<<17) enable/ownership
  writes HANG the controller (write never completes, no soundcard, progressive wedge).
  Downstream does them inside a full init sequence (framer→MGR→INTF→PGD→COMP enables)
  that mainline's qcom_slim_ngd_setup lacks.
- Boot U (qmidbg16u): pgd_enable param default OFF (stable); experiments cmdline-driven.
- Stats: apps-ch-pipes 0x1f80 (bus ports 7-12, port_b identity for 0-5); PGD stat shows
  pipes 7-12 auto-assigned; params live at /sys/module/slim_qcom_ngd_ctrl/parameters/.
- Next: code-study the downstream init order (slim-msm-ctrl.c enable path vs mainline
  setup/power_up), find the prerequisite write, one-boot A/B with netconsole.
- Also watch: no-playback wedge appeared on R/S/T but not Q (correlates with the PGD
  writes — confirm gated-off on U).
Details: `docs/evidence/2026-08-17-qmi-boots/boot-RST-pgd-writes-hang.md` +
`boot-Q-adsp-watchdog-pgd-ownership.md` + `boot-P-slim-connect-stall-analysis.md`.

**2026-08-17 late night (Aurel, third shift) — CRASH EVIDENCE CAPTURED: SLIM CONNECT_SINK stall.**
Boot O hung at the logo: the MODULES=n olddefconfig sweep (632 m->y flips)
regressed early boot. Fixed by rebuilding from the Aug 16 config backup
(.config.bak-20260816-adsp-athdbg) + netconsole only = Boot P (qmidbg11p).
Boot P boots, ADSP comes up, and the first netconsole-captured crash shows:
playback start stalls the SLIMbus NGD TX on the CONNECT_SINK user message
(MC 0x2d, mt 2, LA 0xcf = codec) -> silent death (no panic reached
netconsole; dmesg stream lost to missing local dir).
Two candidates + Boot Q plan: `docs/evidence/2026-08-17-qmi-boots/boot-P-slim-connect-stall-analysis.md`.
Evidence: `.../boot-P-netconsole-crash.txt`.
Key facts: nest listener `nc -u -l -p 6666 >> /tmp/joanrun/netconsole-qmidbg11p.txt`;
phone ssh = `sshpass -f /tmp/pmos-pass ssh user@172.16.42.1` (sudo via SUDO_ASKPASS=/tmp/askpass.sh);
nest iface = `ip addr add 172.16.42.2/24 dev enp0s29u1u5 && ip link set up`.
**Next: Boot Q breadcrumbs + candidate toggles (reconf_passthrough, portb_rewrite) + timeout unwedge + pstore.**

**2026-08-17 night (Aurel, second shift) — PLAYBACK PATH OPENED.**
Boots J–L took the playback lane from EINVAL to a completed aplay:
- The "no backend DAIs enabled" wall was the DAPM mixer gates: the
  intercon routes exist (routing comp = every link's platform), but the
  FE walk stops because mixer input paths start disconnected. Enable
  `SLIMBUS_0_RX Audio Mixer MultiMedia1` (amixer) and the FE opens.
  A UCM profile automates this on real systems.
- The AFE port start error 0x9 needed TWO fixes: kernel sets
  `slimbus_dev_id = AFE_SLIMBUS_DEVICE_1` in q6afe_slim_port_prepare
  (v9 patch; mainline left it 0), and `SLIM RX0 MUX` = `AIF1_PB` so the
  codec exposes its SLIM channels to the machine driver (else the CPU
  dai channel map stays empty and the firmware rejects the port).
- With all three: `aplay hw:0,0 48k stereo` completes. The phone then
  crashed (fell to the bootloader) — teardown path suspect (BE shutdown /
  port stop / slimbus teardown), evidence lost with the RAM boot.
- Still missing for AUDIBLE sound: joan DT has no `audio-routing`
  (db845c has it) and the codec-side mixer sequence (RX INT0_1 MIX1 INP0
  = RX0, RX INT0 DEM MUX = CLSH_DSM_OUT, SPK PA) — see Boot L notes.
- DAC (ES9218P): headphone-path-only. **CORRECTION 2026-08-21: es9218p.c is
  NOT in mainline** -- there is no ES9218P support upstream at all. The file
  in our tree is OUR reverse-engineered port (local commit `dbd7d8f4d`,
  Lance-approved, a deliverable): a never-probed skeleton with
  `CONFIG_SND_SOC_ES9218P` unset.
Details: `docs/evidence/2026-08-17-qmi-boots/boot-L-playback-opened.md`;
patches v6–v9 in out/ (v9 sha256 2b19d41f...); ledger K182+ to be
appended. Kernel tree DIRTY with the v9 debug stack (breadcrumbs + gates
+ dev-id fix).
**Next: teardown-crash hunt + codec-side DAPM for first audible sound.**
Also queued: upstream-shaped q6core fix; WLAN re-confirmation boots;
cellular lane (IPA data / SMS / native-IMS research per Lance 2026-08-17).

The original Ember handoff follows, preserved below.

- **From:** Ember Nymbrand (agent-ember) · Claude-Code:claude-opus-5 · 2026-08-16 (session C)
- **Full detail:** `docs/ember-handoff-2026-08-16b-pd-mapper-fixed-qmi-is-next.md`
- **WLAN detail:** `docs/ember-wlan-delta-recovered-2026-08-16.md` →
  **CONFIRMED ON HARDWARE:** `docs/ember-wlan-confound-confirmed-2026-08-16.md`

## State

Everything is banked and pushed.

| | |
|---|---|
| `ghfork/joan/latest-clean-test` | `7187fbbb5` (full history) |
| `ghfork/master` | `63a15f526` (device-verified only; history amended 2026-08-16) |
| kernel tree | `~/vibe-coding-projects/coding/linux-mainline-v30-usb-otg`, branch `joan/usb3-otg-bringup`, clean |
| build dir | `/data/buildcache/kbuild/build-adsp-only` — build **in place**, no `cp -a` |
| test image | `~/joan-images/boot-joan-snd-pdm.img` on nym-nest |
| Deck | Shared Tasks board 4, card **98** |

Phone: LG V30 `LGUS9986e606d55` on nym-nest. **RAM boots only — never flashed.**
Recover with `adb reboot` or a 10 s power hold.

## Do this first

### Lane A — WLAN — ✅ DONE 2026-08-16, positive

`wlan0` comes up from committed state (`7187fbbb5`) with both symbols cleared,
and passively scans **84 BSSs** (54× 2.4 GHz, 30× 5 GHz). QMI service 69 present
at t+10 s. Full writeup: `docs/ember-wlan-confound-confirmed-2026-08-16.md`.

The driver confirms the config itself:
`kconfig debug 0 debugfs 0 tracing 0 dfs 0 testmode 0`.

Modem crash **closed**: 0 fatal errors over a 56-min window with 6 repeated 5 GHz
scans (`max_freq=5785` every time). `519646f01` (withhold 5845 MHz) confirmed —
the Aug-14 baseline crashed every 20-28 s; 3362 s covers ~120-170 intervals.

**Remaining WLAN work** — the lane is reopened, not finished:
1. Re-confirm the modem fix across *separate boots* (this was one 56-min boot;
   it kills the fluke reading but not boot-to-boot nondeterminism).
2. The real target is the fragility: why is bring-up timing-sensitive enough that
   enabling logging loses the race? Start from
   `docs/ember-wifi-modem-crash-rootcaused-2026-08-14.md` (MSA permission vs
   modem watchdog, ~2.5 s).
3. Both symbols must stay **off** in any image meant to have Wi-Fi. That is a
   footgun for the next person who turns them on to debug — worth a ledger note.
4. `tqftpserv` is staged from tmpfs every boot; Lance approved installing it.

### Lane B — audio, and the wall moved (STILL OPEN — start here)

The PD lookup fix landed and is **verified on device**: `avs/audio` now resolves
and the audio PD reports `SERVREG_SERVICE_STATE_UP`. Still no ALSA card. The
blocker is now **below SLIMbus**:

```
qcom,slim-ngd-ctrl 171c0000.slim-ngd: QMI wait timeout
PDR: msm/adsp/audio_pd register listener txn wait failed: -110
```

The ADSP never registers **QMI service 769 (SLIMbus control service)** — checked
with `qrtr-lookup` across three boots. APR over the same GLINK edge works fine
(all four Q6 services register), so this is specific to QMI/QRTR.

Investigate the QMI layer to the ADSP. **Not** the sound node, **not** SLIMbus.
Open questions: why QMI transactions time out at `-110` while APR is healthy;
whether the ADSP needs something before it starts its SLIMbus service; whether
a `tms/pdr_enabled` equivalent is wanted (joan's `modemr.jsn` advertises it,
`mpss_root_pd` does not carry it).

Worth trying alongside: now that PD maps work, add
`qcom,protection-domain = "msm/adsp/audio_pd"` to the Q6 service nodes, as
sdm845 does. It was omitted on a false premise.

## Resolved: the false PD-maps claim is fixed

`719e34de5` claimed *"msm8998 does not run the audio PD split -- its firmware
carries no PD maps."* False; joan ships six. Lance approved amending, so master
was rewritten: `719e34de5` → `a72f66c1d`, and `ghfork/master` is now
`63a15f526`. Verified message-only — both old and new histories resolve to tree
`f16de7d1a`. The corrected body says the property is dropped because the
*kernel's* msm8998 PD table had no ADSP domains, cites `adspua.jsn`, and points
at revisiting `qcom,protection-domain`.

⚠️ **`joan/latest-clean-test` still carries the original `c43b281a5` with the
wrong body.** It was not rewritten — that would force-push six commits of the
shared full-history branch. Fix it when preparing the series for upstream, or
ask Lance.

## Bring-up sequence on device

```sh
# after every phone reboot the USB net link must be rebuilt by hand:
sudo ip link set enp0s29u1u5 up
sudo ip addr add 172.16.42.2/24 dev enp0s29u1u5

# then, from nym-nest (sshpass -f /tmp/pmos-pass, sudo needs -tt):
scp ~/joan-images/staging/adspfw/* user@172.16.42.1:/tmp/adspfw/
echo /tmp/fwpath > /sys/module/firmware_class/parameters/path
echo start > /sys/class/remoteproc/remoteproc1/state
```

`~/joan-images/staging/fastboot-adsp.sh`-style orchestration exists at
`/tmp/fastboot-adsp.sh` on nym-nest — it does Android → RAM boot → net → ADSP in
one shot, ADSP started at 33 s.

## Don'ts — each of these cost real time

- **Don't `cp -a` a build dir and add `KCFLAGS`.** Read `.<obj>.cmd` first to see
  what the dir was actually built with. Adding `-ffile-prefix-map` changed every
  argv and cold-missed ccache: 2200 objects / 20+ min vs 5 objects / 7m40s in
  place.
- **Don't use `deferred_probe_timeout=0`.** It makes
  `driver_deferred_probe_check_state()` return `-ETIMEDOUT` for genpd and iommu
  lookups (`drivers/base/dd.c:292`). Use a large value — `300` worked. But the
  default `10` *will* drop the sound card before a hand-started ADSP exists.
- **Don't judge audio from an ADSP restart.** `echo stop` times out waiting for
  shutdown and the PD listener then fails; only fresh boots are meaningful.
- **Don't trust `grep -c "[p]attern"` for "is anything using this".** Your own
  shell command line matches. Bit me again this session.
- **Don't assume a `-dirty`-looking image is the one you think.** Check the
  version string in the actual file; several neighbours were `-dirty` and the
  working one was not.

## Unrelated but settled

`build-snd-pdm` deleted (5.6 GB) with Lance's approval.

The monthly `duperemove` pass was running for the whole session (started
2026-08-15 07:12; `/home` ~9 h, `/data` still going at 29.5 h) and made all disk
timings noisy — **check `systemctl is-active duperemove.service` before blaming a
build.** It is doing real work, not spinning: `/data/buildcache/kbuild` is
**661 GB logical across 85 build trees**, while the whole `/data` filesystem
occupies only 457 GB — so sharing has already reclaimed 200 GB+, and `/data`
used fell 486 → 457 GB over ~5 h of this session.

**Done 2026-08-16:** `-q` added to `/usr/local/sbin/duperemove-run.sh` with
Lance's approval (backup at `duperemove-run.sh.bak-20260816`). Without it the
pass logged **3.1 M journal lines** (1.5 GB of journal) to the same disk it was
deduping. Takes effect next monthly run; the in-flight pass keeps its old argv.

**Still open, needs Lance:** 85 kernel build trees in `/data/buildcache/kbuild`
is the actual driver of runtime. Pruning dead ones would shorten every future
pass. Not urgent for space — dedup is already reclaiming it.

Assisted-by: Claude-Code:claude-opus-5
Date: 2026-08-16
