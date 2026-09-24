# Handoff 2026-09-24 — cleanup, USB-C, camera, jack detection

Kernel: `linux-lg-v30-joan` branch `claude/lucid-dijkstra-bxx3r9`, draft
PR #11, targeting `joan/latest-clean-test` (see "PR base" below). **Nothing in this handoff
has been booted.** Every changed object builds clean with clang `W=1`,
checkpatch is clean (bar the missing human sign-off), `dt_binding_check`
passes for every new/changed schema, and `CHECK_DTBS` on
`msm8998-lge-joan.dtb` shows only findings already present in
`msm8998.dtsi`. Commits carry `Assisted-by:` and no `Signed-off-by:` —
Lance adds his own.

## What the branch contains (on top of master `ab54ef668`)

1. **Bring-up instrumentation removed** (~1,100 lines: JOAN-DBG, cmdline
   bisection gates, SLIMbus NGD module params/PGD experiments, IPA counters),
   keeping the four real NGD fixes and the APR/voice fixes. Details in the
   PR description.
2. **q6voice** response correlation, locking, -EBUSY (closes #9/#10's gaps).
3. **Bindings/schema debt**: `ess,es9218p`, `lg,sw43402`, q6 voice services,
   msm8998 NoC (restored), `lge,joan`, APSS WDT, OSM (`qcom,msm8998-osm`),
   CPU OPP names.
4. **IPA v3.1 system header table** (`59d590845da`): mainline set
   `ROUTE_DEF_HDR_TABLE` (system table) but never programmed its base with
   `IPA_CMD_HDR_INIT_SYSTEM`, so the IPA read header data from IOVA 0 —
   the 0x38 reads `ipa.lowmem` papers over. The scratch (now default-on for
   v3.1, `ipa.lowmem=-1/0/1`) stays until **a boot with `ipa.lowmem=0`
   confirms cellular data still works**.
5. **USB-C** (see below). 6. **Headphone jack** (see below). 7. **Camera**
   ([docs/camera/README.md](camera/README.md)).

## USB-C

- PMI8998 Type-C port for TCPM (`qcom_pmic_typec_pmi8998.c`, new
  `port_probe` hook), PMI8998 VBUS in `qcom_usb_vbus` (waits on
  `OTG_STATUS`, backs out, sets Qualcomm's `ENG_BUCKBOOST_HALT1_8_MODE`),
  `qcom_smbx` leaves the port register to the port driver, pmi8998/msm8998
  DT nodes, joan: dual-role connector (Try.SNK in hardware as LG does,
  OTG 1.25 A, 5 V PDOs only, PD PHY on L24), dwc3 role switch defaulting to
  gadget, **SuperSpeed** with the QMP PHY doing orientation.
- Built on Caleb Connolly's unmerged PMI8998 TCPM series
  (gitlab.com/sdm845-mainline/linux `caleb/pmi8998-tcpm-next`); the pmi8998
  DT nodes are his nearly verbatim, credited with links. His authorship /
  sign-off are **not** carried (an automated policy blocked committing
  under his name) — Lance's call as submitter.
- The V30's PMI8998 is **v2.1** (downstream dmesg), so Qualcomm's
  v2.0-only CC2-removal workaround does not apply.
- **Required kernel config for any RAM boot of this branch** — the msm8998
  USB3 PHY driver is `phy-qcom-qmp-usbc`, built by
  `CONFIG_PHY_QCOM_QMP_COMBO` (since the 2024 driver split), which can only
  be `y` with `CONFIG_TYPEC=y`. pmaports `config-lge-joan.aarch64` needs:
  `CONFIG_TYPEC=y`, `CONFIG_PHY_QCOM_QMP_COMBO=y`, `CONFIG_DRM_AUX_BRIDGE=y`
  (verified with `olddefconfig`; nothing else changes). Otherwise dwc3
  waits for its usb3-phy forever and there is no USB at all.

### Correction to the 2026-08-15/16 notes (branch `aurel/earpiece-k2-handoff-20260824`)

`ember-2026-08-15-usbc-audio-camera-host-survey.md` gives
`CONFIG_PHY_QCOM_QMP_USB=y` as the prerequisite, and
`ember-handoff-2026-08-16-audio-bringup-and-wlan-negative.md` concludes the
"modular-PHY theory is dead" because the SuperSpeed test still lost USB with
it. **That symbol does not build the msm8998 USB3 PHY** (see above) — the
build config had `CONFIG_PHY_QCOM_QMP_COMBO=m`, so the theory was never
tested, and it remains the likely cause of that failure. dwc3 falls back to
peripheral when no role provider exists, so `dr_mode="otg"` was not it.

## Headphone jack detection

Symptom (Aug notes): the jack registers and the boot-time state is right,
but live insert/remove edges never arrive, on either HPHL polarity.

- **`a00b7dc` (WCD934x INTR_LEVEL init) was a no-op** and is reverted: the
  LEVEL registers are the regmap-irq chip's type-config registers and
  `regmap_irq_sync_unlock()` rewrites all four whenever a child IRQ is
  requested. Downstream uses pulse for every MBHC source anyway.
- Ruled out against LG's kernel: IRQ pin (TLMM 54, level-high, pull-down),
  INTR registers, the MBHC field map, init sequence, pull-up, debounce,
  bias/RCO clock, moisture threshold (reset value already LG's 24 kΩ),
  switch polarity (ground NC fix from `68c8b96` kept), and the ES9218P —
  `hph-sw` is the DAC's HIFI_MODE2 pin, not a jack switch, and LG keeps the
  DAC unpowered between plugs.
- LG's joan MBHC calibration applied: 1.5 V headset threshold, buttons
  80/130/240/450 mV.
- **Leading suspect**: the SLIMbus NGD is runtime-suspended when audio is
  idle, so the jack IRQ thread must wake it to read the codec status (the
  same MBHC code works on sdm845 with the same codec and pin). Test:

  ```sh
  N=/sys/devices/platform/soc@0/171c0000.slim-ngd/qcom,slim-ngd.1/power
  grep -E "wcd934x|mbhc" /proc/interrupts; cat $N/runtime_status
  # plug in, wait 2 s, unplug:
  grep -E "wcd934x|mbhc" /proc/interrupts
  dmesg | grep -iE "nobody cared|Disabling IRQ|IRQ status|wrong state" | tail
  echo on > $N/control   # keep SLIMbus awake; repeat plug/unplug
  grep -E "wcd934x|mbhc" /proc/interrupts; echo auto > $N/control
  ```
  Counts moving only with `control=on` → SLIMbus wake path; `wcd934x_irq`
  moving but not `mbhc sw intr` → status read failing; nothing either way →
  the signal isn't reaching the SoC.

## Hardware test checklist (in this order)

1. RAM boot with the three config changes above: USB gadget still comes up.
2. USB-C: phone as sink on a PC (gadget), then an OTG adapter + USB stick
   (host; VBUS on, `lsusb`), then flip the plug (SuperSpeed both ways).
3. Jack detection recipe above.
4. `ipa.lowmem=0`: cellular data still works → the scratch can go.
5. Camera: `media-ctl -p`, imx351 probe/chip ID, test pattern, frames;
   flash via `/sys/class/leds/white:flash`.

## Not done yet (next)

- **DisplayPort alt mode**: mainline msm DP has no msm8998 descriptor or
  binding; mmcc-msm8998 already has the DP clocks (parents `dplink`/`dpvco`
  from a DP PHY); the msm8998 DP PHY at 0xc011000 (serdes 0xc011c00)
  matches qmp-usbc's QCS615 USB3+DP layout, so the path is a
  `qcom,msm8998-qmp-usb3-dp-phy` variant with downstream
  `mdss-dp-pll-8998` tables, the DP controller (0x0c990000), DPU INTF_0,
  gpio-sbu-mux (TLMM 100 enable, TLMM 80 select), connector altmodes.
  Reference: sdm845-mainline `caleb/axolotl-dp-alt`. "USB 3.1": the QMP PHY
  on msm8998 is a USB 3.0/3.1 Gen 1 (5 Gb/s) PHY; there is no Gen 2.
- Wide/front camera drivers (tables banked), lens actuator/OIS/laser AF.
- Fingerprint (FPC1022; LG DT has only reset TLMM 27 / IRQ TLMM 121 /
  LVS2 — the SPI bus is TrustZone's), SLPI sensors (accel/gyro/mag/prox/
  light via SSC), NFC (pn547), SAR (sx9320), charger (bq25898s), haptics
  (DW7800).
- pmaports: the config change above; rename `lge-joan` → `lg-joan` to match
  other LG devices; bump the kernel pin once PR #11 lands.

## PR base

`master` takes only device-verified fixes; `joan/latest-clean-test` is the
full working history, whatever the commits add or remove (Lance,
2026-09-24). Nothing here is verified, so PR #11 is retargeted to
`joan/latest-clean-test`, with that branch merged into the PR head.

Assisted-by: Claude-Code:Claude Opus 5.5
Date: 2026-09-24
