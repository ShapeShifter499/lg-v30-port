# Handoff 2026-08-16: audio brought up to the codec; WLAN bisect closed negative

- **Written-by:** Ember Nymbrand (agent-ember)
- **Agent-harness:** Claude-Code:claude-opus-5
- **Date:** 2026-08-16, America/Los_Angeles
- **Authorization:** Lance authorized RAM boots + tests for the session, and
  explicitly approved the ES9218P port and the pushes recorded below.

## Banked

| what | where |
|---|---|
| all 4 commits | `ghfork/joan/latest-clean-test` → `dbd7d8f4d` |
| 2 device-verified commits only | `ghfork/master` → `0315abb74` |
| firmware repo | no change needed — see below |

`master` deliberately carries only the two commits proven on hardware (the
msm8998 audio services and the joan audio path). The CAMSS resource tables and
the ES9218P driver are **not** on `master`: both compile but neither has ever
probed.

**Firmware repo needs nothing.** `owner-firmware-lge-joan/` is gitignored by
design; the repo tracks manifests, not blobs. `owner-firmware-sources.tsv`
already has all 11 `adsp.*` entries with size and sha256, so the extraction is
reproducible. Nothing was added this session.

## Audio: from nothing to the codec identifying itself

Start of session: joan had **no audio nodes at all** and mainline msm8998 had
no SLIMbus and no APR/Q6 services. Now, all device-verified:

```
remoteproc remoteproc1: remote processor adsp is now up
qcom,apr ...: Adding APR/GPR dev: aprsvc:service:4:3 / 4:4 / 4:7 / 4:8
qcom,slim-ngd-ctrl 171c0000.slim-ngd: SLIM SAT: Rcvd master capability
wcd934x-slim 217:250:1:0: WCD934x chip id major 0x108, minor 0x1
```

Every blocker was a missing DT value recovered from LG downstream, or a config
symbol left `=m` where a RAM boot cannot load it. In order:

1. **ADSP firmware absent from pmOS** (`-2`). Present in `firmware-lge-joan`;
   stage to tmpfs and point `firmware_class.path` at it. No rootfs write.
2. **`adsp_mem` was 27 MB, the generic msm8998 value.** joan's own downstream
   says **30 MB**, and the firmware's relocatable PT_LOAD span is exactly
   `0x1e00000`. Fixed, plus the venus/mba/slpi chain.
3. **Codec had no power rails** → dummy regulators → no logical address. All
   five come from `vreg_s4a_1p8` (downstream `pm8998_s4`).
4. **No reset GPIO** → still no logical address. `tlmm 64`. **This is what
   made the codec answer.**
5. **No soundwire child** → `Failed to locate of_node`. Added.
6. **Whole ASoC layer `=m`** → nothing that creates a card could load.
   `SOUNDWIRE`, `SND_SOC_SDM845`, `SND_SOC_WCD934X`, `QDSP6` now `=y`.
7. **`q6asmdai`/`q6afedai` had no child DAI nodes** → `No dais found in DT`,
   `-EINVAL`. Added.

### Where it stops

```
platform sound: deferred probe pending: msm-snd-sdm845: MultiMedia1:
    error getting cpu dai name
```

No ALSA card yet. The machine driver cannot resolve the CPU DAI name for
MultiMedia1. Everything below it is up. **This is the single next thing to
fix.** Likely candidates: the `dai@N` reg values not matching what
`sdm845.c` expects for the frontends, or the sound-node link structure needing
the `platform`/`codec` phandles the driver looks up by name.

The `qcom,sdm845-sndcard` compatible is deliberate — `sdm845.c` implements
exactly this topology and its match table says not to grow the list, which is
why db845c and yoga-c630 reuse it. Revisit only if msm8998 needs behaviour it
does not provide.

### Quad DAC (ES9218P)

Driver written and compiling: `sound/soc/codecs/es9218p.c`, ~290 lines.
**No ES9218P support exists anywhere upstream**, and the only ESS Sabre part in
tree (`es9356`) is SoundWire, so it shares no bus model with this I2C part —
there was no usable relative to start from. Written against upstream idioms
using downstream's register map, not ported from LG's 3700-line driver.

joan hardware: I2C **0x48** on `i2c@c175000` (BLSP1 QUP1); GPIOs power
(pm8998 10), hph-sw (pm8998 12), reset (pmi8998 2). Speaker amp is a separate
TFA98xx at I2C 0x34 on `i2c@c1b5000`.

Unprobed, and cannot be until playback works — it sits *downstream* of the
WCD9340 on the headphone path. The volume scale and mute polarity come from
downstream tables, not a datasheet.

## WLAN: bisect completed, negative — and the baseline is unreproducible

Both surviving candidates were reverted, built and booted **three times each**.
WLFW (QMI service 69) stayed absent every time:

| reverted | boots | result |
|---|---|---|
| `8aab25b4b` (interconnect gnoc + IPA) | 3 | absent |
| `519646f01` (ath10k withhold 5845 MHz) | 3 | absent |

Then the control that should have been run first: **building `d05e70c5e484`
itself** — the commit whose prebuilt image brings `wlan0` up — with the same
toolchain and config. It **also fails** (2 boots), and its DTB is byte-identical
to the working image's.

**So the 25 commits were never the cause.** The working image reports
`d05e70c5e484-dirty`: built from uncommitted changes that no longer exist (no
worktree, no stash, no saved patch). A clean build of that commit does not
reproduce the behaviour.

**The only artifact that has ever brought `wlan0` up cannot be rebuilt from any
committed state.** That is a provenance problem, not a code one.

Hardware is fine: LineageOS Wi-Fi connects at 243 Mbps, RSSI −46. Also ruled
out: LineageOS having claimed the radio first.

**Recommendation:** stop bisecting. Either hunt the lost `-dirty` delta, or
accept clean `d05e70c5e484` as the baseline and debug WLFW registration
directly with `ath10k_core.debug_mask` and QMI tracing.

## USB-C

The SuperSpeed + `dr_mode="otg"` + `usb-role-switch` variant **kills USB
entirely** — kernel boots, pmOS runs with working display and touch, but no
gadget ever enumerates. Confirmed with `CONFIG_PHY_QCOM_QMP_USB=y`, so the
earlier modular-PHY theory is dead; the DT change itself is the cause. Most
likely `dr_mode="otg"` with no role-switch provider on this SoC.

Next experiment: `dr_mode="host"`, which needs no role provider, tested
**alone**. Reverted to USB2/peripheral in the tree meanwhile.

Still blocked upstream regardless: no VBUS regulator and no PMI8998 TCPM in
mainline, so bus-powered host mode and automatic role detection both need new
driver work (extend `qcom_smbx`, whose register range already covers PMI8998's
Type-C block).

## Camera

Fully specified, compiles, never probed. `docs/msm8998-camss-port-map.md` has
the complete hardware map, the downstream→mainline clock mapping, the rates
(VFE is **three OPP levels** 480/576/600 MHz, not a flat list) and the supply
topology (mostly GDSCs → power-domains, not regulators).

msm8998 CAMSS is the sdm660 generation and differs in exactly four ways;
`sdm630.dtsi` is the worked reference, not `sdm660.dtsi` (which has no camss
node). Still needed: a DT node, SMMU stream IDs, GDSC mapping. Sensors
(IMX351, S5K3M3, HI553) have no upstream drivers and are a separate milestone.

## Process notes worth carrying

- **Five separate `=m` traps** this session. On a RAM boot nothing modular can
  load. Check this *first* when a subsystem is silently absent.
- **Validate the baseline before comparing against it.** ~20 boots were spent
  comparing my builds to a prebuilt binary without ever confirming I could
  rebuild that binary. I could not.
- **One change per boot.** Bundling the ADSP and USB changes cost a
  power-cycle and made the result unattributable, after I had written
  "change one thing at a time" into that very file.
- **Retracted this session:** tqftpserv as the WLAN key; ath10k
  module-vs-builtin; `QCOM_PD_MAPPER`; "the memory relayout hung the SoC"
  (it did not — Lance confirmed pmOS was fully usable, only USB was missing).

Assisted-by: Claude-Code:claude-opus-5
Date: 2026-08-16
