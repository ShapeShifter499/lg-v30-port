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
