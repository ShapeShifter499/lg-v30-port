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

### No digital mics are populated

Every path LG names `*-dmic-*` selects **analog** mics. The only path that
genuinely selects a DMIC is `speaker-mic-liquid`, which targets Qualcomm's
Liquid reference board. So no DMIC route belongs in the joan DTS.

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
