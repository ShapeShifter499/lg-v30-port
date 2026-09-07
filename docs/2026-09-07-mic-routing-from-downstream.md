# joan microphone routing, read out of the stock mixer paths

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-09-07

## Why this exists

`ALPHA-STATUS.md` lists microphones as not working, and the port notes have
calls/VoLTE blocked on the mic path. Playback is now solved -- with the ADSP
kept alive by `q6core.skip_versions=1` the WCD9340 enumerates and both the
loudspeaker and the earpiece were confirmed by ear on 2026-09-06. Capture is
what remains, and the UCM profile we ship has no capture devices at all: only
Speaker, Earpiece and Headphones.

The routing did not need reverse engineering in the hard sense. Stock Android
carries it in plain XML, and every control it names also exists in mainline's
`wcd934x`.

## Source

`/vendor/etc/mixer_paths_tavil.xml` (155642 bytes) read over adb from a retail
LG-US998 running stock LineageOS with working audio. Verified against
`sound/soc/codecs/wcd934x.c` at the pinned kernel commit.

## The map

Analogue mics, each on its own decimator and SLIMbus TX slot:

| use | path | ADC | decimator | SLIM TX |
|---|---|---|---|---|
| handset (bottom) mic | `amic1` | ADC1 | DEC6 | TX6 |
| headset mic | `amic2` | ADC2 | DEC0 | TX0 |
| speaker mic | `amic3` | ADC3 | -- | -- |

`handset-mic` and `headset-mic` are aliases: they contain nothing but
`<path name="amic1"/>` and `<path name="amic2"/>` respectively.

Full control sequence for the handset mic:

    AIF1_CAP Mixer SLIM TX6   1
    SLIM_0_TX Channels        One
    CDC_IF TX6 MUX            DEC6
    ADC MUX6                  AMIC
    AMIC MUX6                 ADC1
    IIR0 INP0 MUX             DEC6

and for the headset mic:

    AIF1_CAP Mixer SLIM TX0   1
    SLIM_0_TX Channels        One
    CDC_IF TX0 MUX            DEC0
    ADC MUX0                  AMIC
    AMIC MUX0                 ADC2
    IIR0 INP0 MUX             DEC0

The four digital mics all share DEC7/TX7 and differ only in the DMIC MUX
selection, so only one may be active at a time on that decimator:

    AIF1_CAP Mixer SLIM TX7   1
    CDC_IF TX7 MUX            DEC7
    SLIM_0_TX Channels        One
    ADC MUX7                  DMIC
    DMIC MUX7                 DMIC0 | DMIC1 | DMIC2 | DMIC3   <- dmic1..dmic4
    IIR0 INP0 MUX             DEC7

## Every control exists upstream

Checked against `wcd934x.c` at the pin:

    AIF1_CAP Mixer   present      CDC_IF TX6 MUX   present
    ADC MUX6         present      AMIC MUX6        present
    IIR0 INP0 MUX    present      SLIM TX6         present

So this is a one-to-one translation into UCM `SectionDevice` entries with
`cset` lines, not a driver change. Mainline already logs these mux names --
the "ASoC: mux CDC_IF TX9 MUX has no paths" messages on our boots are the same
namespace, simply unrouted because nothing selects them.

## What to do with it

Add capture devices to `HiFi.conf` alongside the three outputs, following the
same enable/disable discipline the existing devices use (each path enables only
its own controls and tears them down on disable). Start with the handset mic,
since that is the one a call needs.

Not claimed: none of this has been exercised on pmOS yet. The sequences are
what stock uses on the same silicon, and the controls exist, but no capture has
been attempted on a mainline boot.

## Follow-up, same day: headset switch, in-line mics, and a third built-in mic

Extended from the stock **device tree** (the ten DTBs appended to the retail
`boot.img`), which carries what `mixer_paths_tavil.xml` does not.

### There are three built-in mics, not two

LG's factory test path `mictest-allmic` captures **ADC1, ADC2, ADC3 and ADC4**
together, and the four `camcorder-*` paths use ADC1 + ADC3 + ADC4. The stock
`qcom,audio-routing` names them:

| widget | bias | LG's name |
|---|---|---|
| AMIC1 | MIC BIAS1 | Handset Mic (bottom) |
| AMIC2 | MIC BIAS2 | Headset Mic (in-line) |
| AMIC3 | MIC BIAS3 | Handset 2nd Mic (top) |
| AMIC4 | MIC BIAS4 | Handset 3rd Mic |

Our DTS only routed AMIC1..3. AMIC4 reaches ADC4 through the codec's
`AMIC4_5 SEL` mux, so using it needs `cset "name='AMIC4_5 SEL Mux' AMIC4"`.

`camcorder-0`/`-90` map ADC3 to channel 0 and ADC1 to channel 1;
`camcorder-180`/`-270` swap them. That orientation-dependent channel
assignment is the whole of LG's "uses both mics together" for video — the rest
of what that marketing describes is ADSP processing, not routing.

### Digital mics: open question, corrected

An earlier revision of this note (and of the DTS comment) said flatly that no
digital mic is populated. That was stated too strongly. The evidence is mixed:

*Against a DMIC.* Every path LG names `*-dmic-*` selects **analog** mics.
`speaker-mic-liquid`, which genuinely selects DMIC2, targets Qualcomm's Liquid
reference board. And `mictest-allmic` — the factory test, which one would
expect to exercise every fitted mic — uses only ADC1–ADC4.

*For a DMIC.* The four `camcorder-*` paths do select `DMIC0` on TX8, in a real
use case rather than a reference-board one. And the stock DTB sets
`qcom,cdc-dmic-sample-rate = <4800000>` (dtc renders the bytes as the garbage
string `"", "I>"`; decoded it is `0x00493E00`).

Both of the latter also appear in Qualcomm's generic 8998 configuration, which
is the likelier explanation, so no DMIC route is added — but it is left out
pending evidence, not because absence was proven.

### Headset switch (MBHC)

Stock values, identical across all ten board revisions:

```
qcom,msm-mbhc-hphl-swh   = <1>            normally open
qcom,msm-mbhc-gnd-swh    = <0>            normally closed
qcom,mbhc-audio-jack-type = "4-pole-jack"
qcom,msm-mbhc-moist-cfg  = <0 0 1>
lge,msm-mbhc-extn-cable  = <0>
qcom,cdc-micbias1-mv = <0xabe>  2750       qcom,cdc-micbias2-mv = <0x7d0>  2000
qcom,cdc-micbias3-mv = <0xabe>  2750       qcom,cdc-micbias4-mv = <0xabe>  2750
```

Qualcomm's encoding is **1 = normally open, 0 = normally closed**. An earlier
revision of our DTS comment had that inverted (it called `hphl-swh = <1>` "NC")
and left `gnd_swh` at mainline's default `true`, which writes the wrong value
into `WCD_MBHC_GND_PLUG_TYPE`. That is a candidate cause of the live
insert/remove IRQ never behaving, and is now fixed with
`qcom,ground-jack-type-normally-closed`.

All four micbias rails were on mainline's 1800 mV fallback rather than LG's
values. MICBIAS2 is the consequential one: `wcd934x` uses `common.micb_mv[1]`
as `cfg->micb_mv`, so MBHC's jack-type and button thresholds scale with it.

### In-line remote buttons

`sound/soc/qcom/sdm845.c` already creates the jack and maps
`BTN_0..BTN_3` to `KEY_PLAYPAUSE`, `KEY_VOICECOMMAND`, `KEY_VOLUMEUP`,
`KEY_VOLUMEDOWN`, and `wcd934x` supports eight buttons — but without
`qcom,mbhc-buttons-vthreshold-microvolt`, `wcd_dt_parse_mbhc_data()` defaults
`btn_high[0..7]` to 500000, so **every button compares equal and decodes as
BTN_0**. Three of the four keys were unreachable. Fixed with the standard
Qualcomm 75/150/237 mV ladder, which `qcom,wcd934x.yaml` documents.

Not adding the `"MIC BIAS2", "Headset Mic"` route yet, though stock has it:
`sdm845.c` pin-switches that widget from jack state, and while jack detect is
unreliable a "no jack" report would pull MIC BIAS2 down and silence headset
capture. Worth revisiting once insertion reporting is confirmed.

## Global (US998) vs H932: no odd deviation

Checked three ways.

1. **Same DTB.** Both pmaports devices set
   `deviceinfo_dtb="qcom/msm8998-lge-joan"` and build from one DTS.
2. **Downstream DTBs vary only by PCB revision.** The ten in the stock
   `boot.img` share one `qcom,msm-id` and differ across `qcom,board-id`
   `0x308..0xf08`. Excluding phandles, **ten lines** differ between revisions:
   USB-C SBU select, `fcc-max-ua`, battery id and thermal GPIO, and
   `dac,use-internal-ldo`. No audio routing, no MBHC, no micbias.
3. **Vendor audio config is byte-identical bar one path.** Extracted from
   `us998-pie-system.img` and `h932-pie-system.img`:

   | file | differing lines |
   |---|---|
   | `audio_platform_info.xml` | 0 |
   | `audio_policy_configuration.xml` | 0 |
   | `mixer_paths_tavil.xml` | 2 |

   The two lines are `voice-tty-full-headset-mic`: H932 uses
   `ADC2 Volume 20` / `DEC0 Volume 84` against the global model's `10` / `64`.
   TTY is a US carrier accessibility requirement and T-Mobile certifies its own
   gain, so this is a carrier difference, not a hardware one.

Conclusion: one shared DTS is correct, and nothing here justifies splitting it.

## Noise cancellation: what is and is not portable

The routing ports 1:1. The processing does not.

LG's noise suppression, echo cancellation and two-mic beamforming run **inside
the ADSP**, in topologies selected by ID and parameterised from proprietary
ACDB calibration data. Mainline's `q6adm` opens every stream with
`NULL_COPP_TOPOLOGY` and has no ACDB parser, so none of it is reachable without
reimplementing that and shipping LG's blobs.

The practical replacement is userspace. Alpine already ships the WebRTC AEC
backend (`libspa-aec-webrtc.so`, from `webrtc-audio-processing-2`) but **not**
the module that drives it — `pipewire-echo-cancel` is a separate subpackage and
was never in our depends. Adding it plus a drop-in gets noise suppression,
high-pass, gain control and echo cancellation on the mic. The four keys that
backend understands are exactly:

```
webrtc.noise_suppression   webrtc.high_pass_filter
webrtc.gain_control        webrtc.mobile_mode
```

The two-mic beamformer that older `webrtc-audio-processing` had is gone from
the v2 API, so `DualMic` gives two raw channels and nothing beamforms them.
Beamforming would have to be a filter-chain of our own.

## Status

Committed, none of it booted:

* kernel DTS — micbias, ground switch, AMIC4 (`joan/mbhc-headset-mic-v2`)
* `linux-lge-joan` — `0002-joan-micbias-mbhc-amic4.patch`, applies clean to the pin
* `alsa-ucm-conf-lge-joan` — `Mic`, `Headset`, `DualMic` on `hw:x,1`
* `device-lge-joan{,-h932}` — `pipewire-echo-cancel` + drop-in

First test should be raw capture through the UCM devices before trusting the
PipeWire layer.

## ADSP noise suppression: it is reachable after all

The earlier conclusion in this note — that LG's NS/AEC/beamforming needs ACDB
and is therefore out of reach — was half right and led to the wrong plan.

### What ACDB actually is

The ADSP builds a COPP's processing chain from a **topology definition carried
in its own firmware**, named by an ID in `ADM_CMD_DEVICE_OPEN_V5`. ACDB
calibration does not create that chain; it *retunes* modules the chain already
contains. So naming a topology is on its own enough to instantiate the modules
with their firmware defaults, and no ACDB parser is required to get there.

Mainline never did, because `q6routing.c` hardcoded `NULL_COPP_TOPOLOGY` for
every stream. That is a request for a bit-transparent chain — which is exactly
why mainline capture on these SoCs is raw mic and nothing else.

`q6adm_open()` already took `topology`, `app_type` and `acdb_id` parameters.
Only the caller was fixed.

### Which topology, from LG's own data

Rather than trust remembered constants, the IDs were counted in LG's
calibration files pulled off the retail vendor image:

| file | topology found | count |
|---|---|---|
| `Handset_cal.acdb` | `VPM_TX_DM_FLUENCE` `0x00010F72` | 8 |
| `Headset_cal.acdb` | `VPM_TX_SM_ECNS` `0x00010F71` | 1 |
| `Speaker_cal.acdb` | `VPM_TX_DM_FLUENCE` | 1 |
| RX paths (`General`, `Headset`, `Speaker`) | `DEFAULT_COPP_TOPOLOGY` `0x00010314` | 7/17/10 |

That is both a verification of the IDs and a statement of which topology LG
considered correct for which input. Our UCM follows it: `SM ECNS` for a single
mic, `DM Fluence` for the pair.

### What was actually changed

`q6routing` gains a `TX COPP Topology` enum control (`None`, `SM ECNS`,
`DM Fluence`, `QMIC Fluence`, `DM RFECNS`), defaulting to `None` so nothing
changes for anyone who does not ask. Playback is untouched.
`q6adm_find_matching_copp()` already keys on topology, so flipping the control
opens a fresh COPP.

**This is the one change in the set that can fail closed.** If the ADSP
rejects a topology, the COPP open fails and that input goes silent rather than
merely unprocessed. Recovery is one command:

```
amixer -c0 cset name='TX COPP Topology' None
```

### What is still out of reach

Pushing LG's *tuning* — mic spacing, beam direction, per-device NS
aggressiveness — needs two things we do not have:

1. `ADM_CMD_SET_PP_PARAMS_V5` in `q6adm`. Mainline implements only
   `DEVICE_OPEN_V5`, `DEVICE_CLOSE_V5` and `MATRIX_MAP_ROUTINGS_V5`. This is
   maybe 150 lines of ordinary APR code.
2. An ACDB parser. The files are a proprietary keyed heap that
   `libacdbloader.so` walks. This is the real work, and it is a project on its
   own.

Note also that ACDB **is per-model**, unlike the Bluetooth firmware:
`Handset_cal.acdb` is 674039 bytes on US998 and 670571 on H932. If we ever do
parse it, it needs per-device packaging.

Until then the ACDB blobs are inert, so they are deliberately **not** packaged.

## Codec-side quality: two dead ends worth recording

* **TX high-pass filter.** Mainline `wcd934x_codec_enable_dec()` hardcodes
  every decimator to `CF_MIN_3DB_150HZ`. Downstream exposes a per-decimator
  cutoff. 150 Hz is a sensible voice default that removes handling rumble, so
  this is a limitation rather than a defect — no change made.
* **IIR0 "Band1..5".** LG sets these, and mainline implements the
  get/put handlers, but IIR0/IIR1 are the **sidetone** filters: their output
  feeds the RX interpolators, i.e. mic-into-earpiece during a call. They are
  not a capture EQ and do not affect recorded audio.

The capture-side gains that do matter — `ADCn Volume` and `DECn Volume` — are
set explicitly per device in the UCM profile.
