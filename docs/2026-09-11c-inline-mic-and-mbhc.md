# joan: the in-line mic, and why MBHC never detects the jack

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-09-11

Measured with a real 4-pole headset (in-line mic plus a play/pause button)
physically inserted and removed many times during the session.

## Answer

The in-line mic cannot work yet, and the reason is four layers down from the
mic itself. Every layer was measured, not assumed.

1. **ADC2 and the headset mic path are healthy.** With the path forced on, a
   capture returns 93% nonzero samples at about -51 dBFS — a live converter's
   noise floor, not digital silence — and MICBIAS2 reads enabled at LG's 2.0 V
   (`ANA_MICB2 = 0x54`, the 0x40 enable bit set). Compare the working bottom
   mic, which gives -4.7 dBFS with a 61-87x spike on a 1 kHz tone.
2. **It hears nothing because the jack is never switched to 4-pole**, so the
   mic contact is not presented to AMIC2.
3. **The jack is never switched because MBHC never detects insertion.**
4. **MBHC never detects insertion because ground detection is disabled**, and
   nothing in mainline ever enables it.

## The measurements

**No interrupt ever fires.** All five MBHC interrupts are registered and have
never been taken, across many physical insertions:

     115  wcd934x_irq   8  Edge  mbhc sw intr            0
     116  wcd934x_irq  10  Edge  Button Press detect     0
     117  wcd934x_irq  11  Edge  Button Release detect   0
     118  wcd934x_irq  12  Edge  Elect Insert            0
     119  wcd934x_irq   9  Edge  Elect Remove            0
     113  msmgpio      54  Level wcd934x_irq             1   <- parent, once at probe

**No register changes either.** Sampled with the headset fully removed and
again fully inserted, byte for byte identical:

    0614=b5  0615=09  0616=00  0617=00  0618=00  0619=10  061a=18  061b=30

This is not a cache artefact: `drivers/mfd/wcd934x.c` marks `ANA_MBHC_MECH`,
`ANA_MBHC_ELECT`, `ANA_MBHC_ZDET` and `ANA_MBHC_RESULT_1..3` volatile, so the
debugfs reads went to hardware.

**Decoding `MECH = 0xb5`** against `wcd934x.c`'s field table:

| bit | field | value | |
|---|---|---|---|
| 0x80 | `L_DET_EN` | 1 | enabled |
| **0x40** | **`GND_DET_EN`** | **0** | **disabled** |
| 0x20 | `MECH_DETECTION_TYPE` | 1 | |
| 0x10 | `HPHL_PLUG_TYPE` | 1 | normally open, matches stock |
| 0x08 | `GND_PLUG_TYPE` | 0 | normally closed, matches stock |
| 0x04 | `HS_L_DET_PULL_UP_COMP_CTRL` | 1 | |
| 0x01 | `SW_HPH_LP_100K_TO_GND` | 1 | |

The plug-type bits are correct — they match LG's `hphl-swh = 1` /
`gnd-swh = 0`. Ground *detection*, however, is off.

## The mainline gap

`WCD_MBHC_GND_DET_EN` is declared in the field table of **every** WCD codec
driver — `wcd934x`, `wcd937x`, `wcd938x`, `wcd939x`, `pm4125` — and in
`wcd-mbhc-v2.h`'s enum. **No code in the tree ever writes it.** It is defined
and never used.

joan's jack is ground-normally-closed, so mechanical insertion detection
depends on that path. With `GND_DET_EN` clear it is never armed, which is
consistent with everything measured: no RESULT change, no interrupt, no input
event, no kcontrol change.

This is a hypothesis with good supporting evidence, not a proven cause.
`MECH_DETECTION_TYPE` is also set and the arming of insertion-versus-removal
has not been traced, so the bit may not be the whole story.

## Two other findings on the way down

* **`Headset Mic Switch` must be forced on.** `sdm845.c` pin-switches that
  widget from jack state. With detection dead the pin stays off, and the
  capture is then *exactly* zero rather than a noise floor — the ADC powers up
  and DAPM tears it straight back down (`ANA_AMIC2` `ac` -> `2c` mid-capture).
* **Something reclaims MICBIAS2 two to three seconds into every capture**
  (`ANA_MICB2` `0x54` -> `0x14`, the enable bit cleared). Even with working
  detection this would truncate headset recording, so it needs fixing
  separately. MBHC owns MICBIAS2 for its own detection, which is the obvious
  suspect.

## Correction to the earlier record

`2026-09-11-pipewire-cutover-and-audio-stack.md` §8 says the micbias and
ground-switch DTS fixes "have still never been booted". **That is wrong.**
They are present in the booted kernel `2f1308c271d8`:

    qcom,micbias2-microvolt = <2000000>
    qcom,ground-jack-type-normally-closed
    qcom,mbhc-buttons-vthreshold-microvolt = <75000 150000 237000 500000>

So MBHC is correctly configured from DT and still does not detect. That makes
this a more interesting problem than "an unbooted patch", and it is why the
investigation went to the register level.

## Next

Set `GND_DET_EN` in `wcd934x`'s MBHC init and retest insertion. The regmap
debugfs is read-only here (`REGMAP_ALLOW_WRITE_DEBUGFS` unset), so this needs
a driver change and a rebuild rather than a live poke.

If that gives detection, three things land together: jack reporting, the
in-line mic, and the in-line button — the button interrupts are registered and
idle for the same reason.
