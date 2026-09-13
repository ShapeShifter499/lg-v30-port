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

## INTR1 delivery WORKS — the fault is specific to the MBHC source

Tested by generating real WCD-routed traffic: UCM `HiFi`/`Mic` (built-in mic,
AMIC1, WCD9340) then `arecord -D hw:0,1`. Capture succeeded (384044 bytes), so
the mic path also works on r18.

    before capture:  136 msmgpio 54 = 0    138 slim = 0    139 mbhc sw intr = 0
    after  capture:  136 msmgpio 54 = 2    138 slim = 1    139 mbhc sw intr = 0

The codec asserted INTR1, the parent handler ran, regmap-irq demuxed to the
`slim` child and it was handled. **The whole interrupt path is functional.**
This also independently validates the LEVEL work: `slim` shows `Level` in
/proc/interrupts and fired *and was serviced*, with no one-shot-then-silence.

Two notes on method:

- `arecord -D hw:0,0` (MultiMedia1) fails with `Invalid argument`; `hw:0,1`
  (MultiMedia2) is the working capture FE.
- Do NOT grep /proc/interrupts for bare "slim": it also matches the SoC's
  `slim_qcom_ngd_ctrl` slimbus controller, which was at 66191 and climbing
  throughout. That is a different interrupt from the WCD's `slim` child and
  conflating them makes the WCD look far busier than it is.
- pulseaudio is NOT on this image. joan moved to PipeWire
  (`pipewire`/`wireplumber`/`pipewire-pulse` all running); the "kill
  pulseaudio first" note from 2026-09-11 is obsolete and killing it is a no-op.
- The loudspeaker is a TFA9872 on tertiary MI2S, per UCM. Speaker playback does
  NOT traverse the WCD and cannot be used to test WCD interrupt delivery.

### Where that leaves it

Every source on INTR1 works except MBHC. MBHC's steady-state configuration is
byte-identical to downstream. So the remaining difference is almost certainly
not *what* mainline writes but *how*: the order, timing, or a latch/toggle in
downstream's MBHC init sequence that leaves the mechanical comparator armed,
which a register dump of the settled state cannot reveal.

Next: diff downstream's `wcd_mbhc_initialise()` / `wcd_mbhc_start()` write
sequence against mainline's, rather than the resulting register values.

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5

## r19: configuration now byte-identical to downstream, and detection STILL fails

pkgrel 19 (kernel `8454b5f74bca`, `joan/mbhc-micb-ramp`) added the missing
`mbhc_micb_ramp_control(true)` to `wcd_mbhc_initialise()` and dropped r18's
GND_DET_EN. Verified live on the phone:

    0624 ANA_MICB2_RAMP   8c    (was 00 -- now exactly LOS's value)
    0614 ANA_MBHC_MECH    b5    (GND_DET_EN gone -- exactly LOS)
    0615 ANA_MBHC_ELECT   09    (exactly LOS)
    loaded snd-soc-wcd-mbhc  52c45a28 (r19)

**Every register in wcd934x's MBHC field map now matches the stock kernel.**
Lance plugged the headset in, pressed the button, unplugged. Every counter
still zero, parent included; both jack kcontrols still `off`.

### This is the conclusive negative for the configuration theory

Mainline's MBHC is now configured identically to a kernel that detects this
jack on this hardware, and it still does not detect. **Register configuration
is not the cause.** Every register-level hypothesis this session has produced
is therefore retired, and the register-diff approach has been taken as far as
it goes.

The micbias-ramp patch stays worth keeping on its own merits -- the callback
having a single unreachable call site is a real defect on wcd934x/937x/938x/
939x/pm4125 -- but it is not the jack fix, and the commit message already says
so rather than claiming otherwise.

### Remaining differences, all OUTSIDE the MBHC field map

| addr | name | mainline | LOS |
|---|---|---|---|
| `0712` | CLK_SYS_MCLK2_PRG1 | **00** | **a0** |
| `0603` | ANA_RCO | 80 | 00 |
| `0720` bit2 | MBHC_NEW_CTL_1 DETECTION_DONE | 0 | 1 |
| `0721` | MBHC_NEW_CTL_2 HS_VREF | 2 | 1 |

`MBHC_CTL_RCO_EN` (MBHC_NEW_CTL_1 bit7) is set on both, so the MBHC RCO itself
is enabled either way. But **MCLK2 is never programmed in mainline**, and the
insertion debounce is 96 ms of counting that needs a clock to run. A detection
FSM whose debounce timer never advances would present exactly as this does:
correctly armed, comparator configured, and no interrupt ever generated.

Next lead: the MBHC clock domain -- what `CLK_SYS_MCLK2_PRG1 = a0` enables
downstream, and whether the MBHC debounce/FSM is clocked from it. That is
source and datasheet work, not another register dump.

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5

## Clock gating refuted; the codec is fully cleared

Hypothesis: INTR1 had fired exactly once all day -- during a mic capture --
and never while idle, so perhaps the codec can only report jack events while
MCLK is up.

Test: 90 s mic capture with per-10 s sampling, Lance plugging the headset and
pressing the button mid-capture.

    t=0..80   parent=2  mbhc_sw=0  btnpress=0  electins=0  jack=off
    t=90      parent=4  mbhc_sw=0  btnpress=0  electins=0  jack=off

MCLK was demonstrably up (capture ran; the parent ticked 2->4 at stream stop)
and **no MBHC source moved**. Clock gating is not the cause.

### Everything in the driver's control is now verified correct

| property | evidence |
|---|---|
| configuration | byte-identical to the stock kernel across wcd934x's whole MBHC field map |
| clocked | interrupts fire on the same INTR1 line during capture |
| armed | `L_DET_EN = 1` in `ANA_MBHC_MECH` |
| sources unmasked | `INTR_PIN1_MASK1 = f2` |
| interrupt path | parent fires, regmap-irq demuxes, `slim` child serviced |
| hardware | LOS detects this jack on this silicon, `h2w state = 1` |

All measured, none inferred. And the jack still does not detect.

### ES9218P pin model is correct -- not a hidden routing switch

joan wires three GPIOs to the ES9218P (`power` pm8998 gpio 10, `reset`
pmi8998 gpio 2 ACTIVE_LOW, `hph-sw` pm8998 gpio 12). "HPH_SW" reads like an
analog switch routing the jack between WCD and DAC, which would explain
everything -- but downstream's own driver says otherwise (`es9218.c:434`):

    hph_switch_gpio;                    //HIFI_MODE2
    reset_gpio=H && hph_switch_gpio=L   --> HiFi mode
    reset_gpio=L && hph_switch_gpio=H   --> Bypass mode

`hph_sw` *is* MODE2, so mainline's model is right. Bypass mode was tested
earlier today with a physical replug: negative.

## Hypotheses eliminated this session, all by measurement

1. Interrupt plumbing -- parent fires and demuxes, proven during capture
2. Masking -- MBHC sources unmasked on both
3. Plug-type polarity -- matches the stock DTB, registers confirm
4. Jack / machine-driver wiring -- input device and kcontrols exist
5. ES9218P routing -- tested in Low Power Bypass, negative
6. Ground detection (`GND_DET_EN`) -- clean negative, and downstream runs it at 0
7. Moisture detection -- `MOISTURE_STATUS` clear
8. `MECH_DETECTION_TYPE` -- mainline's value is correct for an empty jack
9. `FSM_EN` -- likewise correct for an empty jack
10. Micbias ramp -- real defect, fixed in r19, did not fix the jack
11. Clock gating -- refuted with MCLK demonstrably up
12. Hidden analog routing switch -- `hph_sw` is MODE2 per downstream

## What is left

The fault is in the analog path between the jack sleeve and the WCD's L_DET
pin, and nothing in the codec's register space or the driver explains it. The
next step is joan's schematic -- specifically how the jack's detect contact is
routed, and whether anything on that line needs enabling that is not modelled
in DT at all. That is not bench work and not driver archaeology.

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5

## The codec's raw status latch never moves — it is blind at its input

Instrument changed: instead of asking why the interrupt does not arrive, poll
the hardware status registers directly across a physical plug event.

13 samples over ~195 s on r19, with Lance unplugging, replugging and pressing
the button inside the window. **Every sample identical:**

    STATUS0=00 STATUS1=00 MECH=b5 ELECT=09 RES3=10 mbhc_irq=0 parent=0

`INTR_PIN1_STATUS0/1` are the raw latches, read before any interrupt handling.
They never set. So this was never an interrupt-delivery problem, never a
masking problem, and never a configuration problem: **the WCD9340's mechanical
comparator does not register the insertion at all.**

That holds while:

- MBHC registers are byte-identical to the stock kernel
- all three ES9218P GPIOs are byte-identical to the stock kernel
- LOS detects via the *same* `mbhc sw intr` source on the *same* msmgpio 54
  (verified: parent=1, mbhc sw intr=1, h2w state=1)
- the codec is otherwise fully functional: mics, slimbus, audio capture

Note on the instrument: each sample costs ~15 s because it greps a 65536-line
regmap dump five times, so a "3 s cadence, 40 samples" script actually samples
every ~15 s. Budget for that; the wall-clock window is what matters, not the
sample count.

## Next: the ES9218P's internal registers

The one active component between jack and codec whose *internal* state has
never been compared. Mainline's own driver says it is incomplete:

    This control only moves the mode pins.  The register sequences downstream
    runs across a transition (es9218p_sabre_hifi2lpb() and friends) are not
    implemented yet

Correct mode pins with un-programmed internal analog switches would isolate
the jack from the WCD in every mode, which is exactly what the status latch
says is happening. GPIO parity has been established; register parity has not.

Dump and diff: mainline `i2c 0-0048`; on LOS the regmap list shows `7-0008`
and `7-0034`. Then port whatever sequence downstream runs to reach the idle
state, rather than only setting the pins.

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5

## ES9218P register dump — partial comparison only

Mainline exposes the part at `/sys/kernel/debug/regmap/0-0048` (70 registers);
dumped live on r19 in HiFi mode. **LOS cannot be dumped**: its driver binds at
`1-0048` but the `registers` sysfs attribute from `DEVICE_ATTR(registers,...)`
is not present on that build, and there are no i2c-tools on the device. Note
`/sys/bus/i2c/devices/1-0059/registers` DOES exist and is a *haptics* chip
(IC_INFO/FIFO_FULLNESS/HAPTIC_DATA) -- not the DAC. Do not diff it by mistake.

So the comparison is mainline-live against downstream-*source*
(`es9218_RevB_init_register[]`):

| reg | | downstream | mainline |
|---|---|---|---|
| 0x02 | automute config | F4 | 34 |
| 0x05 | automute level | 63 | 68 |
| 0x07 | filter shape | A0 | 80 |
| 0x0b | channelmap/OCP | 90 | 90 |
| 0x0d | THD comp | 00 | 00 |
| 0x1b | gen config | C4 | c4 |

The three that differ are audio-quality settings. None gates an analog detect
line, so porting them is housekeeping, not a jack fix.

`AMP_CONFIG` (0x20) reads 00 in mainline against downstream's 0x02/0x03, but
that is explained rather than a defect: mainline writes `AMP_MODE_HIFI1` inside
`es9218p_amp_power_up()`, which runs from a DAPM `SND_SOC_DAPM_POST_PMU` event
-- i.e. only when a stream actually powers the ES9218P widget.

### Untested: does detection work once the analog path is powered?

Attempted and FAILED to test. `alsaucm set _enadev Headphones` plus
`speaker-test -D hw:0,0` left `AMP_CONFIG` at 00 through the whole run, so the
bring-up never ran and the test exercised nothing. `hw:0,0` (MultiMedia1) is
the same FE that fails for capture; `hw:0,1` is the working one.

To test properly: get a real stream through the ES9218P DAPM widget so
POST_PMU fires and `AMP_CONFIG` goes 00 -> 02, *then* replug. If detection
starts working with the analog stage powered, the fix is about when mainline
brings that path up -- not about downstream's automute/filter values.

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
