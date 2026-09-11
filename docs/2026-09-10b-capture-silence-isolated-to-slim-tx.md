# joan capture: two blockers cleared, silence isolated to SLIMbus TX

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-09-10

Second session of 2026-09-10. **Partially supersedes
`HANDOFF-2026-09-10-next-session.md`** — read that first for the bench access
lanes and the module/SLIMbus/UCM prerequisites, which all still hold, then read
this for the corrected diagnosis. Nothing was written to the SD card.

> **Superseded on 2026-09-11 by `2026-09-11-microphone-capture-works.md`.**
> The microphone works. SLIMbus TX was never broken — every capture measured
> here was taken with `pulseaudio` running on the phone, which is what forces
> the zeros. Sections 1-3 (the channel-count rule, the `out 0` correction, the
> register readback) still stand; the "isolated to SLIMbus TX transport"
> conclusion in §4-§6 does not.

## Headline

The previous diagnosis — "the SLIM capture BE never starts, the whole analog
front end is unpowered" — was **wrong**, and it was wrong because the evidence
was read at the wrong moment. With a valid channel count the BE starts, the
entire DAPM chain powers up, and the codec provably digitises the mic. The
recording is still all zeros. The defect is now isolated to **data transport on
SLIMbus in the TX direction (codec -> ADSP)**.

## 1. Why `arecord` succeeded some sessions and failed others

Not SM_ECNS. The AFE port config carries a channel count taken from the codec,
and the codec reports *every TX port currently enabled on the AIF1_CAP mixer*:

    wcd934x_get_channel_map()  -> counts dai[AIF1_CAP].slim_ch_list
    sdm845_slim_snd_hw_params()-> snd_soc_dai_set_channel_map(cpu_dai, tx_ch_cnt, ...)
    q6slim_set_channel_map()   -> slim.num_channels = tx_num

Those mixer bits are sticky and accumulate across every `alsaucm _enadev` in a
session. After 4.4 h of uptime five were on, so the ADSP was asked for a
5-channel port:

    slim port 16385 cfg: dev 0 rate 48000 width 16 ch 5 fmt 0 map 134/128/135/136
    qcom-q6afe: cmd = 0x100e5 returned error = 0x1    (AFE_PORT_CMD_DEVICE_START)
    AFE enable for port 0x4001 failed -22
    q6afe-dai: fail to start AFE port 3
    ASoC error (-22): at snd_soc_dai_prepare() on SLIMBUS_0_TX

Measured, same boot, `TX COPP Topology` verified `None` by `cget` throughout:

| AIF1_CAP TX ports on | AFE config | result |
|---|---|---|
| 5 (accumulated) | `ch 5` | `AFE enable ... failed -22` |
| TX6 only | `ch 1` | starts clean |
| TX6 + TX7 | `ch 2` | starts clean |

**Clear every `AIF*_CAP Mixer SLIM TX*` before each capture attempt.** Without
that, results are not reproducible between passes, let alone between sessions.
Note `sdm845_be_hw_params_fixup()` independently forces the BE to `channels =
2`, so the AFE count and the ASoC BE count do not have to agree — 1 works.

## 2. `out 0` was a symptom, not the fault

The prior handoff read `AIF1 Capture: Off in 5 out 0` as "no route to an active
sink" and concluded the DPCM backend was never selected. A `dai_out` widget only
counts as an output endpoint while `w->active` is set, which happens at stream
start — so `out 0` is just "no capture is running". It says nothing about
routing.

The graph was complete the whole time. Dumped during a *working* capture, every
hop is `On`:

    [MultiMedia2 - Capture]  State: start   FE S16_LE 1ch 48000
    Backends: - SLIM Capture  State: start  BE S16_LE 2ch 48000

    codec: MIC BIAS1, AMIC1, ADC1, AMIC MUX6, ADC MUX6, CDC_IF TX6 MUX,
           SLIM TX6, AIF1_CAP Mixer, AIF1 CAP, AIF1 Capture
    dsp:   SLIMBUS_0_TX, Slimbus Capture, MultiMedia2 Mixer, MM_UL2,
           MultiMedia2 Capture

Chain as wired, confirmed from the debugfs `out`/`in` edges:

    AMIC1 -> ADC1 -> AMIC MUX6 -> ADC MUX6 -> CDC_IF TX6 MUX -> SLIM TX6
      -> AIF1_CAP Mixer -> AIF1 CAP -> AIF1 Capture -> Slimbus Capture
      -> SLIMBUS_0_TX -> MultiMedia2 Mixer -> MM_UL2 -> MultiMedia2 Capture

## 3. The codec really is digitising

Register readback, not control echo (`/sys/kernel/debug/regmap/217:250:1:0`,
the wcd934x-slim PGD; there is no `regmap/*wcd*` node — find it by that name):

| reg | idle | capturing | meaning |
|---|---|---|---|
| `060e` ANA_AMIC1 | `2c` | `ac` | ADC1 enabled, bit7 |
| `0622` ANA_MICB1 | `23` | `63` | MIC BIAS1 enabled, 0x40 |
| `0a91` TX6_PATH_CTL | `04` | `24` | DEC6 running, bit5 |
| `0a94` TX6_VOL_CTL | `00` | `00` | 0 dB, not muted |
| `0d28` ADC_MUX6_CFG0 | `01` | `01` | ADC1 selected |

Gains are not the cause: `DEC6 Volume` 84/124 and `ADC1 Volume` 12/20.

## 4. The inference that matters

The WAV is **exactly** zero — every one of 288000 samples. A live analog ADC
never produces exact zeros; a quiet room still dithers the LSB. All-zero is not
"silence", it is "no data arrived". That is what points at transport rather than
at the mic, the gains or the topology.

## 5. Ruled out this session

- DAPM routing and graph completeness (§2) — every widget `On`, edges verified.
- Codec analog front end and decimator (§3) — by register readback.
- Interface-device TX port programming. The instrumented line
  `slim-tx port=6 ch=134 payload=0x40 wr 0x118/0x56 rb 0x40/0x5` decodes as
  multi-channel reg `0x118` reading back `0x40` (channel bit 6) and port cfg
  `0x56` reading back `0x5` (`WCD934X_SLIM_WATER_MARK_VAL`). Correct.
- `TX COPP Topology` — `None` by `cget` on every pass that still recorded zeros.
- The bus connect message. With `slim_dbg` on:

      codec-connect mc=0x2c orig_la=0xcf port=6 ch=134     <- CONNECT_SRC
      codec-connect mc=0x2e orig_la=0xcf port=6 ch=0       <- 6.00 s later

  `SLIM_MSG_MC_CONNECT_SOURCE -> SLIM_USR_MC_CONNECT_SRC (0x2c)` is sent for the
  right port and channel and held for the whole capture.
- `joan_pipes` app-port bringup. Forced on at runtime; all twelve pipe connects
  returned 0, bringup logged `pgdla=0xc4`, phone stayed up — still zeros.
- Channel-count mismatch as the *silence* cause: `ch 2` with the BE also at 2
  records zeros just as `ch 1` does.

Also corrected: `docs/2026-08-22-tfa9872-fix-and-slimbus-playback.md` says
`joan_pipes` "defaults to on and should stay on". That is **stale** — the source
is `static bool joan_pipes;` with `MODULE_PARM_DESC(... "default off")`.

Not ruled out: SLIMbus NGD runtime PM. `JOAN-PM` resume/suspend cycles bracket
every capture, and `echo on > .../171c0000.slim-ngd/power/control` did not take
(`runtime_status` reads `unsupported` on that node), so that test was invalid,
not negative. Find the device that actually owns the runtime PM callbacks and
retry.

## 5a. Stock corroboration, and where the XML actually is

**There is a local copy of the stock mixer paths** — no device access needed:

    ~/vibe-coding-projects/coding/joan_lineageos_volte/repos/
        device_lge_joan-common/audio/mixer_paths_tavil.xml

Do not try to mount the phone's `system` partition for it. The eMMC `system`
(sda22, non-A/B, no separate `vendor`) reads as zeros at offset 0 and this
kernel has no EROFS, so it will not mount — and that partition carries the
JoanIms VoLTE bench, so it is not worth poking at.

Its init block corroborates §1 directly: stock **zeroes every**
`AIF1_CAP Mixer SLIM TX9..TX0` at boot before any path enables one, and sets
`SLIM_0_TX Channels One`. Its `ADC1 Volume 12` / `DEC6 Volume 84` are exactly
our live values, and the `amic1` path matches what we drive control-for-control.

So the control layer is not where the difference is. `mixer_paths_tavil.xml`
describes only kcontrols, and ours already match — which is itself evidence that
the remaining gap is below that layer, in SLIMbus data transport.

## 6. Suggested next move

Playback over SLIMbus delivers data — the loudspeaker and earpiece were
confirmed by ear on 2026-09-06. So the bus, the framer and the ADSP data path
all work in the RX direction, and only TX is dead. **Run a playback and a
capture with `slim_dbg=1` and diff the two message sequences.** The missing or
malformed TX step should fall out of the diff, and that is a much cheaper
question than auditing the channel-activate path cold.

Specifically worth checking in that diff:

- whether `qcom_slim_ngd_enable_stream()` (which replaces the generic
  DEFINE/ACTIVATE path via `ctrl->enable_stream`) emits the same
  `SLIM_USR_MC_DEF_ACT_CHAN` / `RECONFIG_NOW` pair for a source port as for a
  sink, and with what `coef`/`exp`;
- `rt->prot`: `slim_stream_prepare()` picks `SLIM_PROTO_PUSH` for playback and
  `SLIM_PROTO_PULL` for capture whenever the rate is not a multiple of the
  framer superframe rate, so the two directions can differ here;
- the untested knobs `portb_rewrite` and `reconf_passthrough`, neither of which
  has ever been exercised for TX.

## Bench state as left

Phone up on the RAM-booted pmOS, uptime ~4.6 h, card `LGV30` registered, gadget
and ssh stable, nothing written to the SD card. Runtime-only changes that a
reboot reverts: `joan_pipes=Y` (its `joan_pipe_done` latch has fired),
`AIF1_CAP Mixer SLIM TX6` the only capture mixer bit on, `TX COPP Topology` None.

Host-key note: the phone's ed25519 key rotates on every RAM boot. Use
`-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null` as the
`scripts/bench-automation/` scripts already do, rather than editing nest's
`known_hosts`.
