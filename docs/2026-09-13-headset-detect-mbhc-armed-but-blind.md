# joan headset: MBHC is armed and correct, and the jack still does not detect

Session: Ember (Claude-Code:claude-opus-5), 2026-09-13, on r16
(`ff98974a67aa`) with Lance physically operating the headset.

STANDING APPROVAL (Lance): always look at the code and reverse engineer stock
ROM/kernel wherever it helps the port.

## The result

With the soundwire-IRQ fix in place, MBHC now arms on every boot. Lance
unplugged and replugged a 4-pole headset and pressed the in-line button,
twice, once in ES9218P HiFi mode and once in Low Power Bypass.

**Every interrupt counter stayed at zero — including the parent.**

    136:  0  msmgpio 54   Level  wcd934x_irq      <- parent INTR1: never asserted
    139:  0  wcd934x_irq 8    Edge   mbhc sw intr
    140:  0  ...  Button Press detect
    141:  0  ...  Button Release detect
    142:  0  ...  Elect Insert
    143:  0  ...  Elect Remove

`Headphone Jack` and `Headset Mic Jack` both read **off** with the headset
physically inserted.

## What this rules OUT

This is the useful part: the interrupt plumbing is no longer a suspect.

- **MBHC is started, not merely initialised.** `ANA_MBHC_MECH = 0xb5` has
  `L_DET_EN (0x80) = 1`, which only `wcd_mbhc_start()` sets. Note for future
  sessions: "all seven MBHC handlers registered" — the signal used as success
  in previous handoffs — only proves `wcd_mbhc_init()` requested the IRQs at
  codec probe. `L_DET_EN` is the bit that proves detection was armed.
- **The sources are unmasked.** `INTR_PIN1_MASK1 = 0xf2`: MBHC_SW_DET (bit0),
  BUTTON_PRESS (bit2) and BUTTON_RELEASE (bit3) are all enabled.
- **Plug-type polarity matches downstream.** joan declares
  `qcom,ground-jack-type-normally-closed` and omits the HPHL property, giving
  `hphl_swh=1 / gnd_swh=0` — identical to the stock DTB's
  `qcom,msm-mbhc-hphl-swh = <1>` / `qcom,msm-mbhc-gnd-swh = <0>`. Registers
  confirm: `HPHL_PLUG_TYPE=1`, `GND_PLUG_TYPE=0`.
- **The jack and its input device exist.** `LG-V30 Headset Jack` on
  `/dev/input/event4`, plus the `Headphone Jack` / `Headset Mic Jack`
  kcontrols, so `snd_soc_card_jack_new_pins()` and the sdm845 machine driver's
  `snd_soc_component_set_jack()` path both ran.
- **The ES9218P is not the gate.** joan's DTS notes that the WCD9340's
  HPHL/HPHR reach the jack only through the ES9218P Quad DAC, which powers on
  in HiFi mode — a good hypothesis for MBHC looking at a disconnected pin.
  Tested: switched `Headphone Mode` to `Low Power Bypass` ("WCD analog passes
  through") and had Lance replug. **No change**, zero counters. Restored to
  HiFi.

## What remains

The mechanical L_DET comparator never asserts INTR1. Everything downstream is
consistent with "the driver has never seen an insertion" and is therefore
symptom, not cause: `FSM_EN (ANA_MBHC_ELECT 0x80) = 0`, MICBIAS2 off
(`ANA_MICB2 = 0x14`, bit6 clear), all RESULT registers zero.

Ordered suspects:

1. **`GND_DET_EN = 0`** (`ANA_MBHC_MECH` 0x40). `wcd934x_mbhc_gnd_det_ctrl()`
   raises it together with `HSG_PULLUP_COMP_EN` during detection, not at arm
   time. Lance already has this parked on `joan/mbhc-gnd-det-experiment` and
   it is decision item 3 — this result is the argument for un-parking it.
2. **The HS_L detect pull-up.** `HS_L_DET_PULL_UP_COMP_CTRL (0x04) = 1` but the
   pull-up current source and its supply want checking against downstream; a
   mech comparator with no pull-up sees nothing regardless of L_DET_EN.
3. **Whether joan's jack-detect pin reaches the WCD's L_DET at all.** Not yet
   established from the schematic or the stock DTB. Everything above assumes
   it does because downstream uses `qcom,msm-mbhc-*`, which is suggestive but
   not proof.

## GND_DET_EN: retested on a clean baseline, and eliminated

Suspect 1 above has now been tested properly. `a54b241e43c9` was cherry-picked
onto the fixed kernel as `joan/mbhc-gnd-det-v2` (`1c0180a108ec`) and shipped as
pkgrel 18.

Why the retest was justified: the original run's parent is `648c5181cbb6`,
which predates `2b6ecf829cd7`. On that tree soundwire could still hold IRQ 8 =
`WCD934X_IRQ_MBHC_SW_DET`, so "every MBHC interrupt reads zero" could not
distinguish *ground detection does not help* from *MBHC was never armed*.

The retest baseline was verified before touching the hardware:

    0614 ANA_MBHC_MECH        f7     (was b5 -- GND_DET_EN and pullup-comp set)
    loaded snd-soc-wcd-mbhc   2ffb0fd1  (r18, the patched module)
    MBHC handlers             7
    all counters              0

Lance then physically unplugged, replugged and pressed the in-line button.
Result: **every counter still zero**, parent `msmgpio 54` included, both jack
kcontrols still `off`, `ANA_MBHC_RESULT_1/2` still `0x00`.

**Ground detection is not the cause on joan.** The original commit reached the
same conclusion and was right, but on evidence that could not support it; this
is the same answer with the confound removed. The commit stays worth keeping
as a dead-code correction (`cfg->gnd_det_en` is assigned nowhere in the tree,
making `mbhc_gnd_det_ctrl()` unreachable on wcd934x/937x/938x/939x) but it is
not a joan fix.

That leaves one suspect standing: **whether joan's jack-detect pin reaches the
WCD's L_DET at all.** Everything else has been measured and ruled out. This is
schematic / downstream-DTB work, not bench work.

## Method note (cost me two rounds)

The python input watcher reported nothing both times **because it was never
running** — `pgrep -f jackwatch.py` matched the `sudo`/`setsid` wrapper, not a
live process, so "watcher pid: 3519" was false confirmation. `ps -o pid,args |
grep -c "[j]ackwatch"` returned 0. The interrupt counters are independent of
the watcher and are what the conclusions above rest on.

A watcher that is not running looks exactly like a jack that is not firing.
Positive-control the channel before trusting its silence.

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-09-13

## BREAKTHROUGH: register diff against LineageOS on the same hardware

Rather than keep guessing at the analog layer, boot the stock OS on the same
phone and diff the codec registers. LOS detects the headset, so whatever bit
differs is the answer.

`adb root` on LOS; the WCD9340 regmap is `/sys/kernel/debug/regmap/tavil-slim-pgd`.

**LOS state at capture: headset INSERTED and detected** --
`/sys/class/switch/h2w/state = 1`, and `getevent -lp` on
`msm8998-tavil-snd-card Headset Jack` shows `SW_HEADPHONE_INSERT*`,
`SW_MICROPHONE_INSERT*`, `SW_JACK_PHYSICAL_INS*` all currently set.
**This proves the hardware path is intact and joan's jack-detect pin does
reach the WCD's L_DET.** The remaining suspect from the previous section is
eliminated; the fault is entirely in the mainline driver.

Same registers, same physical state (headset inserted), both drivers:

| register | mainline r18 | LOS | note |
|---|---|---|---|
| `0409` INTR_PIN1_MASK0 | f2 | f0 | |
| `040a` INTR_PIN1_MASK1 | f2 | f2 | same |
| `0603` ANA_RCO | 80 | 00 | |
| `0614` ANA_MBHC_MECH | **f7** | **95** | see below |
| `0615` ANA_MBHC_ELECT | **09** | **b9** | bit7 FSM_EN: 0 vs **1** |
| `0623` ANA_MICB2 | 14 | 14 | same |
| `0656` MBHC_CTL_CLK | 30 | 30 | same |
| `0720` MBHC_NEW_CTL_1 | 82 | 86 | DETECTION_DONE set downstream |
| `0721` MBHC_NEW_CTL_2 | 06 | 05 | HS_VREF 2 vs 1 |
| `0725` FSM_STATUS | 00 | 00 | moisture clear both |

`ANA_MBHC_MECH` decoded:

| field | mask | mainline | LOS |
|---|---|---|---|
| L_DET_EN | 0x80 | 1 | 1 |
| GND_DET_EN | 0x40 | 1 | **0** |
| MECH_DETECTION_TYPE | 0x20 | **1** | **0** |
| HPHL_PLUG_TYPE | 0x10 | 1 | 1 |
| GND_PLUG_TYPE | 0x08 | 0 | 0 |

### Three conclusions

1. **`GND_DET_EN` is wrong and r18 should be reverted.** Downstream runs it at
   0 while detecting correctly. Independent confirmation of the clean negative
   above.
2. **`MECH_DETECTION_TYPE` is inverted relative to downstream for the same
   physical state, and mainline never initialises it.** Across all of
   `wcd-mbhc-v2.c` there are exactly two writes: the read-and-invert inside
   `wcd_mbhc_swch_irq_handler()` (which cannot run if no interrupt ever
   fires -- a deadlock), and one in `wcd_mbhc_typec_report_unplug()`, gated on
   `cfg->typec_analog_mux`, which joan does not set. So on a non-Type-C device
   the bit is never written at arm time and keeps whatever value it powers up
   with. joan powers up at 1.
3. **`FSM_EN` is 0 in mainline, 1 downstream.**

### The fix to try

`wcd_mbhc_start()` must establish `MECH_DETECTION_TYPE` to match the current
jack state before setting `L_DET_EN`, instead of inheriting the POR value. As
it stands the driver arms itself to watch for the edge that cannot occur:
watching for removal with nothing inserted, so an insertion is never seen, so
the IRQ handler that would flip the bit never runs.

This is a mainline bug affecting every non-Type-C wcd934x/937x/938x/939x
board, not a joan quirk -- the same way `cfg->gnd_det_en` was found to be
unassigned tree-wide.

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5

## Full register diff, both sides with the headset REMOVED

The single-state capture above was not enough to interpret polarity, so both
states were captured on LOS and compared against mainline in the same state.

**The MECH_DETECTION_TYPE hypothesis is REFUTED.** LOS, headset removed, reads
`0614 = b5` / `0615 = 09` / `0619 = 10` -- byte-for-byte identical to mainline.
So the polarity is the opposite of what the single sample suggested:

| | MECH_DETECTION_TYPE |
|---|---|
| LOS, jack empty | 1 (armed to detect insertion) |
| LOS, jack inserted | 0 (armed to detect removal) |
| mainline, undetected | **1 -- correct** |

`FSM_EN = 0` is likewise correct for the empty state; downstream reads `09`
there too. Both of the fixes proposed in the previous section would have been
patches for non-bugs. The second capture cost one `adb` read and prevented
shipping them.

### Every MBHC field-map register, headset removed on both

| addr | name | LOS | mainline | |
|---|---|---|---|---|
| 0411 | INTR_PIN1_STATUS0 | 00 | 00 | same |
| 0609 | ANA_HPH | 0c | 0c | same |
| 0614 | ANA_MBHC_MECH | b5 | f7 | differs *only* by r18's GND_DET_EN |
| 0615 | ANA_MBHC_ELECT | 09 | 09 | same |
| 0616 | ANA_MBHC_ZDET | 00 | 00 | same |
| 0619 | ANA_MBHC_RESULT_3 | 10 | 10 | same |
| 0623 | ANA_MICB2 | 14 | 14 | same |
| 065a | MBHC_CTL_BCS | 01 | 00 | bit0, unmapped in mainline's field table |
| 065b | MBHC_STATUS_SPARE_1 | 00 | 00 | same |
| 06cd | HPH_CNP_WG_TIME | 14 | 14 | same |
| 06ce | HPH_OCP_CTL | 3a | 28 | OCP config |
| 06d2 | HPH_PA_CTL2 | 50 | 50 | same |
| 06d4 | HPH_L_TEST | e1 | e0 | bit0 = HPHL_OCP_DET_EN |
| 06d7 | HPH_R_TEST | e1 | e0 | bit0 = HPHR_OCP_DET_EN |
| 0720 | MBHC_NEW_CTL_1 | 86 | 82 | bit2 = DETECTION_DONE |
| 0721 | MBHC_NEW_CTL_2 | 05 | 06 | HS_VREF 1 vs 2 |
| 0722 | MBHC_NEW_PLUG_DETECT_CTL | a6 | a6 | same |
| 0725 | MBHC_NEW_FSM_STATUS | 00 | 00 | same |
| 0726 | MBHC_NEW_ADC_RESULT | 00 | 00 | same |

**The mechanical detection path is configured identically.** MECH (modulo
GND_DET_EN), ELECT, ZDET, MICB2, PLUG_DETECT_CTL and every RESULT/STATUS
register match. The only differences are over-current protection, a button
threshold, and DETECTION_DONE -- none of which gate insertion sensing.

**Conclusion: the fault is not in MBHC configuration.** It is in interrupt
delivery, or in something outside this regmap.

### Correction to the LEVEL premise of 2026-09-12

The interrupt block diff also corrects something this project has believed
since `abc48a756b0f`. Both that commit and its type-table replacement assumed
downstream programs "source 0 level-high, everything else pulse". Downstream
actually programs all four LEVEL bytes:

| | 0461 | 0462 | 0463 | 0464 |
|---|---|---|---|---|
| LOS | **03** | **e0** | **94** | **80** |
| mainline | 01 | 00 | 00 | 00 |

MBHC_SW_DET is source 8 = LEVEL1 bit0, which is 0 on both, so the MBHC sources
really are pulse in both and this does not explain the jack. But the premise
"downstream sets only bit 0" was wrong, and the type-table fix reproduces only
part of downstream's configuration.

Other interrupt-block differences, none of them MBHC sources: `0400` (LOS 00,
mainline 04), `0409` bit1 = IRQ_MISC (unmasked downstream, masked in mainline
because mainline's table has no MISC entry), `040b`/`040c` unmasking sources
mainline does not implement.

### Next step

Determine whether mainline's INTR1 delivers *any* wcd934x interrupt during
normal operation. The 2026-09-11 handoff records a boot where the parent fired
66 times and demuxed to the slim child, so the path can work. If slim
interrupts still fire on a current kernel while MBHC never does, the fault is
specific to the MBHC source; if nothing fires at all, INTR1 delivery is broken
generally and MBHC is only the visible victim. That is one audio-playback test,
not a rebuild.

`0400` also wants identifying -- mainline sets bit2 where downstream has the
register at zero, and it sits at the base of the interrupt block.
