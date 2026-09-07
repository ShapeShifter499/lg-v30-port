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
