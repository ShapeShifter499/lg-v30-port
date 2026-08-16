# Host-side survey: USB-C / audio / camera lanes on mainline joan

- **Written-by:** Ember Nymbrand (agent-ember)
- **Agent-harness:** Claude-Code:claude-opus-5
- **Date:** 2026-08-15, America/Los_Angeles
- **Scope:** originally source/config analysis only. Superseded in part —
  Lance lifted the WLAN hold and authorized RAM boots the same session; see
  §5 for what the device then revealed.

> **CORRECTION (same day, after device work).** The first version of this
> survey was written against `coding/linux-mainline-v30`, branch
> `joan/battery-fg`. **That is the wrong tree.** It is not ahead of the port's
> build base — it is a divergent, older line. Its `msm8998-lge-joan.dts` is
> 851 lines; the real base (`ghfork/joan/latest-clean-test`, `5fbb6db35`) is
> 947 and already carries ADSP, MSS and IPA wiring the battery-fg copy lacks.
> Two claims below were wrong because of this; both are corrected inline and
> marked **[WAS WRONG]**. Everything sourced from `msm8998.dtsi`, the driver
> tree, the downstream tree or the config is unaffected — those are identical
> across both checkouts.
>
> The lesson is the same one that produced the unbootable kernel in §5: the
> *contents* of an artifact were checked carefully without checking it was the
> *right* artifact.

Trees read (read-only):

- **build base (authoritative):** `coding/linux-mainline-v30-usb-otg`, fresh
  worktree off `ghfork/joan/latest-clean-test` (`5fbb6db35`)
- ~~`coding/linux-mainline-v30` (`joan/battery-fg`, `569fbe2c7`)~~ — divergent;
  do **not** read joan board DTS from here
- sealed keyfix worktree: `coding/linux-mainline-v30-wcn3990-keyfix`
  — verified still at `834154d6b082`, ahead 3, untouched
- downstream: `coding/android_kernel_lge_msm8998`
- config: `lg-v30-pmos-prealpha/.../config-lge-joan.aarch64`
  — **this config has never booted joan; see §5**

Claims are tagged **[CONFIRMED]** (I read the code/DTS) or **[INFERRED]**
(strong evidence, still needs a device or a build to prove).

---

## 0. Cross-cutting blocker: the lanes are built as modules

This is the single most important finding, and it affects **every** lane
including any future RAM-boot Wi-Fi test.

A `fastboot boot` RAM-only image has no rootfs to load modules from. Ember
already hit this with `CONFIG_NF_TABLES` absent / `IP_NF_IPTABLES=m` breaking
in-kernel NAT. The same shape blocks the new lanes: **[CONFIRMED]**

| Option | Current | Consequence on a RAM boot |
|---|---|---|
| `CONFIG_PHY_QCOM_QMP_USB` | `=m` | **USB 3 PHY cannot load → no SuperSpeed** |
| `CONFIG_TYPEC` | `=m` | no Type-C class |
| `CONFIG_TYPEC_TCPM` | `=m` | no port manager |
| `CONFIG_TYPEC_QCOM_PMIC` | `=m` | no Qualcomm PMIC Type-C |
| `CONFIG_SLIMBUS` | `=m` | no SLIMbus → no WCD codec |
| `CONFIG_QCOM_APR` | `=m` | no APR → no Q6 audio |
| `CONFIG_SND_SOC_QCOM` | `=m` | no Qualcomm ASoC machine/platform |
| `CONFIG_VIDEO_QCOM_CAMSS` | `=m` | no camera |

Already builtin and fine: `CONFIG_USB_ROLE_SWITCH=y`,
`CONFIG_USB_DWC3_DUAL_ROLE=y`, `CONFIG_USB_DWC3_QCOM=y`,
`CONFIG_USB_XHCI_PLATFORM=y`, `CONFIG_USB_STORAGE=y`, `CONFIG_HID_GENERIC=y`,
`CONFIG_USB_GADGET=y`, `CONFIG_USB_CONFIGFS=y`,
`CONFIG_USB_CONFIGFS_MASS_STORAGE=y`, `CONFIG_PHY_QCOM_QUSB2=y`,
`CONFIG_PHY_QCOM_QMP=y`.

Note the pattern: `PHY_QCOM_QUSB2=y` (USB 2 PHY) but `PHY_QCOM_QMP_USB=m`
(USB 3 PHY). That is very likely *why* the DTS was pinned to USB 2 — the
USB 3 PHY simply could not come up on a RAM boot. **[INFERRED]**

Also noticed, unrelated to these lanes: `CONFIG_BATTERY_PMI8998_FG is not set`
while joan DTS enables `&pmi8998_fg`. The mainline checkout is on branch
`joan/battery-fg`, so this is presumably in-flight — flagging, not acting.

---

## 1. USB-C lane

The goal breaks into four independent layers. They are **not** equally hard,
and the honest answer is that layers 1–2 are close and layers 3–4 are real
driver work that does not exist upstream.

### What joan currently forces **[CONFIRMED]**

`arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts:520-537`:

```dts
&usb3 {
	status = "okay";
	/* Run USB 2 only for bring-up */
	qcom,select-utmi-as-pipe-clk;
};

&usb3_dwc3 {
	/* Drop the unused USB 3 PHY */
	phys = <&qusb2phy>;
	phy-names = "usb2-phy";
	/* Fastest mode for USB 2 */
	maximum-speed = "high-speed";
	/* Force to peripheral until we can switch modes */
	dr_mode = "peripheral";
};
```

Every one of these is a deliberate bring-up narrowing, not a hardware limit.

### Layer 1 — USB 3 SuperSpeed: **cheap** [INFERRED, buildable]

`msm8998.dtsi` already has a complete, correct USB 3 stack:

- `usb3: usb@a8f8800` — `qcom,msm8998-dwc3`, full clocks/resets/GDSC
- `usb3_dwc3: usb@a800000` — already declares
  `phys = <&qusb2phy>, <&usb3phy>`
- `usb3phy: phy@c010000` — `qcom,msm8998-qmp-usb3-phy`, with aux/ref/cfg_ahb/
  pipe clocks, both resets, and `qcom,tcsr-reg = <&tcsr_regs_2 0xb244>`

So SuperSpeed is: drop the three joan overrides + set
`CONFIG_PHY_QCOM_QMP_USB=y`. No new driver code. This is the highest
value-per-risk item in the whole USB-C lane.

### Layer 2 — host mode / OTG for thumb drives and keyboards: **moderate**

`dwc3-qcom.c` and `dwc3/core.c` both honour a `usb-role-switch` property, and
`CONFIG_USB_ROLE_SWITCH` is already `=y`. **[CONFIRMED]**

So manual role switching via
`/sys/class/usb_role/<ctrl>/role` (or `dr_mode = "host"`) should give a working
xHCI host with `USB_STORAGE` and `HID_GENERIC` already builtin.

**But** — see layer 4. Manual role switch alone will enumerate a
*self-powered* device. A bus-powered thumb drive or keyboard needs VBUS, and
nothing upstream drives joan's VBUS boost.

### Layer 3 — automatic role/orientation detection: **does not exist upstream**

This is the finding that overturns the cheap assumption. I checked whether
`qcom_pmic_typec` could just take a new compatible for PMI8998. **It cannot.**

`drivers/usb/typec/tcpm/qcom/qcom_pmic_typec.c` supports exactly
`qcom,pm8150b-typec` and `qcom,pmi632-typec`, parameterized by
`pmic_typec_resources { pdphy_res, port_res }`, with register bases supplied
from DT (`reg = <0x1500>, <0x1700>` for pm8150b) and all offsets relative.
That *looks* like a one-liner. The register maps say otherwise: **[CONFIRMED]**

| | PM8150B (SMB5) | PMI8998 (SMB2) |
|---|---|---|
| Type-C block | dedicated peripheral @ `0x1500` | folded into **USBIN** @ `0x1300` |
| status regs | `TYPEC_SNK_STATUS` `0x06`, `TYPEC_SRC_STATUS` `0x08`, `TYPEC_MISC_STATUS` `0x0B` | `TYPE_C_STATUS_1..5` @ `USBIN+0x0B..0x0F` |
| config regs | `TYPEC_MODE_CFG` `0x44`, `TYPEC_CCOUT_CONTROL` `0x48` | `TYPE_C_CFG/2/3` @ `USBIN+0x58..0x5A` |
| bit layout | SNK/SRC split | `UFP_TYPEC_*` / `DFP_TYPEC_*` masks |

Sources: mainline `qcom_pmic_typec_port.c` offsets vs downstream
`drivers/power/supply/qcom/smb-reg.h` (`USBIN_BASE 0x1300`,
`TYPE_C_STATUS_1_REG (USBIN_BASE + 0x0B)`, `TYPE_C_CFG_REG (USBIN_BASE + 0x58)`).

Cross-check that pins it: mainline `qcom_smbx.c` — which *does* support
`qcom,pmi8998-charger` — defines `TYPE_C_STATUS_1 0x30B` and `TYPE_C_CFG 0x358`
against a node whose `reg = <0x1000>`. `0x1000 + 0x30B = 0x130B`, exactly the
downstream `USBIN_BASE + 0x0B`. The two independent sources agree.

**Consequence:** PMI8998 Type-C registers are *already inside the address range
owned by the `qcom_smbx` charger driver*. Adding a `qcom,pmi8998-typec` node
would overlap it. The upstream-acceptable shape is therefore to extend
`qcom_smbx` to register a TCPM port / role-switch provider — which is exactly
what downstream `qpnp-smb2` does (one driver owning charging + Type-C + OTG) —
**not** to add a compatible to `qcom_pmic_typec`.

`qcom_smbx` today only writes Type-C role config once in its init sequence
(`TYPEC_POWER_ROLE_CMD_MASK`, `OTG_EN_SRC_CFG_BIT`). It implements no TCPM, no
attach/detach handling, no role switching. **[CONFIRMED]**

### Layer 4 — VBUS boost for host mode: **missing upstream**

`grep -c regulator_register drivers/power/supply/qcom_smbx.c` → **0**.
Mainline registers no VBUS/OTG regulator for PMI8998. **[CONFIRMED]**

Downstream does: `qpnp-smb2.c` has `smb2_vbus_reg_ops`
(`smblib_vbus_regulator_enable/disable/is_enabled`), `smb2_init_vbus_regulator()`,
and a separate VCONN regulator, driving `OTG_BASE 0x1100` — `CMD_OTG_REG`
(`OTG_BASE+0x40`), `OTG_CFG_REG` (`+0x53`), `OTG_CURRENT_LIMIT_CFG_REG` (`+0x52`).

Without this, host mode enumerates nothing bus-powered. **This is the actual
blocker for "plug in a thumb drive or a keyboard."**

### Charging / file transfer

Charging already works (device is charging over USB now on LineageOS, and
`qcom,pmi8998-charger` is upstream and enabled in joan DTS). File transfer is
a gadget-side concern and the config is already complete
(`USB_CONFIGFS` + `USB_F_MASS_STORAGE` + `USB_F_FS`, all `=y`) — that lane is
config-and-userspace, not kernel work.

### USB-C verdict

| Capability | Status |
|---|---|
| Charge from charger | works today |
| File transfer (gadget) | config ready; userspace task |
| USB 3 SuperSpeed | DTS override removal + one `=y`. Cheap. |
| Host mode, self-powered device | likely reachable via `usb-role-switch` |
| Host mode, bus-powered (thumb drive/keyboard) | **blocked** — needs a VBUS regulator that does not exist upstream |
| Automatic role/orientation/PD | **blocked** — needs new PMI8998 TCPM work inside `qcom_smbx` |

---

## 2. Audio lane

Better than the handoff's inventory suggested. The prerequisite is already
half-built upstream.

### ADSP — already present **[CONFIRMED]**

`msm8998.dtsi:3571` has `remoteproc_adsp: remoteproc@17300000`,
`compatible = "qcom,msm8998-adsp-pas"`, full smp2p interrupts, `adsp_mem`
region, `RPMPD_VDDCX`, and a `glink-edge` child labelled `lpass`.
`qcom_q6v5_pas.c:1586` matches it to `msm8996_adsp_resource`.

It is `status = "disabled"` at SoC level, and **three** msm8998 boards already
flip it on: `msm8998-mtp.dts`, `msm8998-fxtec-pro1.dts`,
`msm8998-lenovo-miix-630.dts`. fxtec-pro1 does simply:

```dts
&remoteproc_adsp {
	status = "okay";
};
```

**[WAS WRONG]** The first draft said joan's DTS has *zero* audio-related
nodes. That was read off the divergent `joan/battery-fg` tree. On the real
build base joan **already enables the ADSP**, with firmware wired up:

```dts
&remoteproc_adsp {
	firmware-name = "qcom/msm8998/joan/adsp.mdt";
	status = "okay";
};

&remoteproc_mss {
	firmware-name = "qcom/msm8998/joan/mba.mbn",
			"qcom/msm8998/joan/modem.mdt";
	status = "okay";
};
```

So step 1 of the audio chain below is **already done**. What joan still has
no node for is SLIMbus, the codec, and a `sound` machine node. **[CONFIRMED
against `5fbb6db35`]**

### SLIMbus — missing upstream, but the port looks near-mechanical

`msm8998.dtsi` contains no `slim` node at all (`grep -c slim` → 0).
**[CONFIRMED]**

Downstream `msm8998.dtsi` has it, and the addresses are the interesting part:

| | msm8998 (downstream) | sdm845 (mainline) |
|---|---|---|
| SLIMbus NGD | `0x171c0000`, size `0x2C000`, IRQ 163 | `0x171c0000`, size `0x2c000`, IRQ 163 |
| SLIMbus BAM | `0x17184000`, IRQ 164 | `0x17184000`, IRQ 164 |

Identical base addresses and IRQs. sdm845 uses
`compatible = "qcom,slim-ngd-v2.1.0"`; msm8996 uses `v1.5.0` at a *different*
base (`0x91c0000`). **[INFERRED]** msm8998 is the v2.1.0-generation block and
the node can be lifted from sdm845, changing the `iommus` stream ID to the
msm8998 SMMU.

Caveat, and I want to be explicit about it given the BIMC QoS lesson: matching
base address and IRQ is strong evidence of the same block, **not proof of the
same NGD version**. Downstream just says `qcom,slim-ngd` with no version, so it
does not settle the question. This needs a build + probe to confirm, not
assertion.

### Codec chain

- **WCD934x (the main codec)** — `drivers/mfd/wcd934x.c` exists upstream, and
  downstream has a `sound/soc/codecs/wcd934x` directory, confirming joan is
  tavil-class not tasha-class. **[CONFIRMED]** This is the best-supported piece.
- **ES9218P Quad DAC** — downstream-only (`sound/soc/codecs/es9218p.c`,
  `es9218.c`). **No upstream driver.** **[CONFIRMED]**
- **Speaker amp** — downstream carries `tfa9872/` (not the generic `tfa98xx`;
  the `tfa9879.c` in that tree is a different, unrelated part). No upstream
  driver for tfa9872. **[CONFIRMED]**

### Q6 / APR — present upstream **[CONFIRMED]**

`sound/soc/qcom/qdsp6/` has the full set: `q6afe`, `q6adm`, `q6asm`,
`q6afe-dai`, `q6afe-clocks`, `audioreach`, etc.

### Audio verdict

Dependency chain, in order:

1. ~~Enable `remoteproc_adsp` in joan DTS~~ — **already done** on the real
   build base, with `firmware-name` set. Nothing to do.
2. Add a SLIMbus NGD + BAM node to `msm8998.dtsi` — moderate, sdm845-shaped
3. Wire WCD934x on SLIMbus + a `sound` machine node — moderate, well-trodden
4. Build APR/SLIMBUS/SND_SOC_QCOM as `=y` for RAM boots
5. Quad DAC and speaker amp — **new drivers, nothing upstream**

Headset/speaker audio via WCD934x is a realistic target. **The ES9218P Quad
DAC is not** — that is a from-scratch driver port. I'd treat "sound works" and
"Quad DAC works" as two separate milestones and not promise the second.

### DEVICE FINDINGS (added after RAM-boot testing)

Two hard blockers found on-device, both further along than the survey assumed.

**1. The ADSP firmware is not installed on the phone at all.** **[CONFIRMED]**

```
remoteproc remoteproc1: Direct firmware load for
    qcom/msm8998/joan/adsp.mdt failed with error -2
```

The phone's `/lib/firmware/qcom/msm8998/joan/` has `mba.mbn`, `modem.b0*` and
`wlanmdsp.mbn` — **no `adsp.*` whatsoever**. The complete set does exist in
`coding/firmware-lge-joan` (`adsp.mdt` + `b00`–`b11`, two byte-identical copies,
`adsp.mdt` sha256 `56e90c22…`).

Staging it into tmpfs and pointing `firmware_class.path` at it (the
`verify-v3.sh` technique — no rootfs write) gets past `-2`:

```
Booting fw image qcom/msm8998/joan/adsp.mdt, size 7260
```

**2. …and then it fails on region size.** **[CONFIRMED]**

```
qcom_q6v5_pas 17300000.remoteproc: segment outside memory range
remoteproc remoteproc1: can't start rproc adsp: -22
```

Parsing the ELF32 program headers of `adsp.mdt` (12 phdrs, Hexagon):

| | range | size |
|---|---|---|
| firmware requires | `0x91900000` – `0x93702000` | **30.01 MiB** |
| joan `adsp_mem` | `0x92b00000` – `0x94600000` | 27.00 MiB |

`mdt_loader.c:396` rejects on `offset + p_memsz > mem_size`, which trips on
size **regardless of relocation** — so this is not fixable by moving the base.

**joan's region is not wrong by local standards:** downstream declares
`pil_adsp_mem: pil_adsp_region@0x92B00000 { reg = <0 0x92B00000 0 0x1b00000>; }`
— byte-identical to mainline joan's `adsp_mem`. So either this firmware image
is from a different build than joan's memory map, or downstream shipped a
smaller ADSP image than the one in `firmware-lge-joan`.

**Do not simply enlarge the region.** `adsp_mem` + 30 MiB runs to `0x94a00000`
and collides with `venus_mem` at `0x94600000`; `mpss_mem` bounds it from below
(`0x8b400000`–`0x92b00000`). Making room means relaying out the reserved-memory
map, which is exactly the class of change that hung this SoC three times over
BIMC QoS. Establish the correct ADSP image first.

**Firmware identity settled.** The device's own
`/system/vendor/firmware_mnt/image/adsp.mdt` (LineageOS, sde16 vfat) is
**byte-identical** to the `firmware-lge-joan` copy — both sha256
`56e90c22…`. So the image is correct for joan and the 30 MiB requirement is
real; it is not a wrong-variant problem.

Downstream survives on 27 MiB because its `qcom,lpass@17300000` is
`qcom,pil-tz-generic` with `qcom,pas-id = <1>` — TZ performs the load and
carves its own memory, so the DTS region is effectively advisory. Mainline's
`mdt_loader` enforces it strictly. No mainline msm8998 board declares more:
the SoC default is 26 MiB and mtp/fxtec/miix-630 all inherit it.

### A 30 MiB relayout was tried; the boot failed — but NOT because of it **[2026-08-15]**

> **ATTRIBUTION CORRECTED.** This section originally concluded the relayout
> caused an "instant silent XPU reset". That was **wrong**, and the correction
> matters because the false claim would have permanently scared everyone off
> the correct fix.
>
> The image booted for that test carried **three** changes, not one: the memory
> relayout, the new SLIMbus node, **and** the USB-C DTS change that makes
> `usb3_dwc3` require `phys = <&qusb2phy>, <&usb3phy>`.
>
> The observed symptom was `FASTBOOT_BOOT_RETURNED=0` followed by
> `RESULT=PMOS_USB_TIMEOUT` — i.e. the kernel took the image and then no USB
> gadget ever appeared. The config used for that kernel
> (`build-chan169-d05e70c5e/.config`) has **`CONFIG_PHY_QCOM_QMP_USB=m`**. A
> RAM boot has no module tree, so the USB3 PHY driver can never load, so dwc3
> defers forever waiting on `usb3-phy`, so there is **no USB at all**. That is
> a complete and sufficient explanation of the failure with no memory fault
> involved — and it is the same cross-cutting `=m` blocker documented in §0 of
> this very file.
>
> The phone was therefore most likely running fine and simply unreachable, not
> crashed. It still needed a power-cycle because no channel remained.
>
> **There is no evidence the relayout was harmful.** It was reverted anyway
> (before this was understood); the correct LG-derived values are below and
> remain untested.

**Prerequisite for ANY future test of the USB-C DTS change:**
`CONFIG_PHY_QCOM_QMP_USB=y`. With it `=m`, enabling the USB3 PHY in DT costs
you the entire USB stack on a RAM boot.

### Why it hung, and why there is no easy 3 MB to find

LG's full protection map (downstream `msm8998.dtsi` `reserved-memory`):

| range | size | region |
|---|---|---|
| `0x8b400000`–`0x92b00000` | 119 M | `modem_mem` |
| `0x92b00000`–`0x94600000` | 27 M | `pil_adsp_mem` |
| `0x94600000`–`0x94b00000` | 5 M | `pil_video_mem` |
| `0x94b00000`–`0x94d00000` | 2 M | `pil_mba_mem` |
| `0x94d00000`–`0x95c00000` | 15 M | `pil_slpi_mem` |
| `0x95c00000`–`0x95d00000` | 1 M | `pil_ipa_gpu_mem` |

**Zero gaps** between `0x92b00000` and `0x95d00000`. Growing adsp upward put it
inside `pil_video_mem`, which is firmware-owned — hence the XPU reset. The
mainline `reserved-memory` nodes do not show this, which is precisely why
checking overlap against them alone was insufficient.

**Growing downward is also blocked.** Parsing `modem.mdt` with the kernel's own
`mdt_phdr_loadable()` rules (PT_LOAD, non-hash, non-zero) gives a loadable span
of **exactly 119.00 MiB** = `0x8b400000`–`0x92b00000`. The modem fills its
region byte-for-byte; there is no tail to borrow.

**The loader-side alternative is also closed.** `qcom_q6v5_pas.c:632` sets
`pas->mem_phys = pas->mem_reloc = res.start` straight from `memory-region`, and
`qcom_mdt_pas_load()` relocates (the firmware does carry `QCOM_MDT_RELOCATABLE`).
Relocation moves the base but not the span, and `mdt_loader.c:396` rejects on
`offset + p_memsz > mem_size`. 30 MB of segments cannot be made to fit 27 MB.

Re-verified with the hash filter applied: `adsp.mdt` phdr 1 is the
`QCOM_MDT_TYPE_HASH` segment at `0x93700000` and is correctly excluded; the ten
real PT_LOADs still span `0x91900000`–`0x93700000` = 30.00 MiB exactly.

### RESOLVED: LG gives joan 30 MB, via a per-device override

The 27 MB figure is the **generic** `msm8998.dtsi` value. joan overrides it in
`arch/arm64/boot/dts/lge/msm8998-joan/msm8998-joan-common/msm8998-joan-common-pm.dtsi`,
and moves the whole chain with it:

```dts
&pil_adsp_mem    { reg = <0 0x92B00000 0 0x1e00000>; };   /* 30 MB */
&pil_video_mem   { reg = <0 0x94900000 0 0x500000>;  };
&pil_mba_mem     { reg = <0 0x94E00000 0 0x200000>;  };
&pil_slpi_mem    { reg = <0 0x95000000 0 0xf00000>;  };   /* stays 15 MB */
&pil_ipa_gpu_mem { reg = <0 0x95F00000 0 0x100000>;  };   /* MOVED UP */
```

So the 30 MB requirement derived from `adsp.mdt` is exactly right, and
downstream's PIL arithmetic (`pil_setup_region()` → span of *relocatable*
segments → `pil_alloc_region()`) agrees with mainline's `mdt_loader` to the
byte. Nothing exotic is going on; joan simply needs the bigger region.

### Why the 2026-08-15 attempt hung — and the correct fix

The attempted relayout matched LG **exactly** on adsp / video / mba, then
diverged on the last two:

| region | LG joan (correct) | attempt | |
|---|---|---|---|
| `adsp` | `0x92B00000` + `0x1e00000` | same | ok |
| `venus`/`pil_video` | `0x94900000` + `0x500000` | same | ok |
| `mba` | `0x94E00000` + `0x200000` | same | ok |
| `slpi` | `0x95000000` + **`0xf00000`** | `+0x200000` | **wrong** |
| `ipa_gpu` | **`0x95F00000`** | *not moved* | **wrong** |

The fatal one is the last. With SLPI at its true 15 MB the protected range runs
`0x95000000`–`0x95F00000`, and LG therefore relocates `pil_ipa_gpu_mem` to
`0x95F00000`. Mainline joan puts `gpu_mem` at `0x95c00000` — **inside** that
range — and also carries plug nodes `reserved@95215000` (to `0x95700000`) and
`reserved@95800000` (to `0x95c00000`) that were sized against the *old* SLPI
extent. Shifting adsp without moving `gpu_mem` and re-cutting those plugs put
live allocations inside firmware-owned RAM → silent XPU reset, USB dropped
mid-boot, power-cycle required.

**Correct change (not yet applied — device was offline):** port LG's five
overrides verbatim, *and* move mainline's `gpu_mem` to `0x95F00000`, *and*
re-cut `reserved@95215000` / `reserved@95800000` against the new SLPI extent.
The existing joan DTS comment already warns that mainline `gpu_mem`/`wlan_msa`
"lie inside LG's SLPI range and must move before zap shader / wifi bringup" —
that warning is exactly this trap, and it was in the file the whole time.

Note `wlan_msa` at `0x95700000` also falls inside the enlarged SLPI range and
needs the same treatment; it is currently working, so moving it is a change
that must be validated alongside, not assumed.

**SLIMbus node added** (not yet probed): `slim-ngd@171c0000` +
`dma-controller@17184000` in `msm8998.dtsi`, both `status = "disabled"`,
compiled and verified in the joan DTB (IRQ 163/164 present, dma phandles
resolve). It cannot be exercised until the ADSP runs, since the NGD is
ADSP-managed.

### Microphone

Mic hangs off the same WCD934x SLIMbus TX path, so it comes with step 3 — no
separate driver. It cannot be verified without the device, and there is no
existing mic verification of any kind on this port.

---

## 3. Camera lane

The handoff called this "no `qcom,msm8998-camss` in upstream CAMSS", which is
true, but the situation is better than that implies.

### Upstream CAMSS has no msm8998 entry **[CONFIRMED]**

`camss.c` of_device_id table lists msm8916, msm8939, msm8953, msm8996,
qcm2290, qcs8300, sa8775p, sc7280, sc8280xp, sdm660, sdm670, sdm845, sm6150,
sm6350, sm8250, sm8550, sm8650, x1e80100. No msm8998.

### But the hardware generation *is* supported

Downstream `msm8998-camera.dtsi`: **[CONFIRMED]**

- `qcom,vfe48` — VFE 4.8
- `qcom,csid-v5.0`
- `qcom,csiphy-v5.0`
- ISPIF present

Upstream `sdm660_resources` → `.version = CAMSS_660`, with
`csiphy_res_660` / `csid_res_660` / `vfe_res_660` **and** `ispif_res_660`.
sdm660 is the VFE 4.8 / ISPIF generation.

**[INFERRED]** msm8998 CAMSS is the same generation as sdm660, so adding
`qcom,msm8998-camss` is a *resource-table addition* (clocks, regs, IRQs,
regulators, per-SoC counts) modelled on `sdm660_resources` — not a new ISP
driver. That is real work but bounded and well-precedented.

### Sensors — all three missing, each with a near sibling **[CONFIRMED]**

| joan sensor | upstream driver | nearest sibling present |
|---|---|---|
| IMX351 (rear) | **absent** | `imx355.c` |
| S5K3M3 (rear) | **absent** | `s5k3m5.c` |
| HI553 (front) | **absent** | `hi556.c` |

Siblings are suggestive, not drop-in. I would not assume register
compatibility between S5K3M3 and S5K3M5 without a datasheet or downstream
register table.

Also worth noting: downstream carries a `hi553` node only under **lucy**
(a different LGE msm8998 device), and joan's camera DTSI
(`msm8998-joan-camera_rev_0.dtsi`) did not yield sensor names to my grep
patterns — LGE uses indirection there. The joan sensor list in the prior
handoff should be re-verified against that file before anyone writes a driver.

### Camera verdict

Longest lane by a wide margin. CAMSS core is a tractable port; three sensor
drivers are not, and camera is the one lane where I'd say the honest estimate
is "not close."

---

## 4. Suggested sequencing

Nothing here needs the phone until step 3, and step 3 needs Lance's approval.

1. **Config sweep** — flip the RAM-boot-blocking options to `=y`
   (`PHY_QCOM_QMP_USB`, `TYPEC*`, `SLIMBUS`, `QCOM_APR`, `SND_SOC_QCOM`,
   `VIDEO_QCOM_CAMSS`). Pure config, host-buildable, benefits every lane.
2. **USB 3 + role switch DTS** — remove the three joan overrides, add
   `usb-role-switch`. Host-buildable, no device.
3. **First combined device test** — *only when Lance asks*: the held WCN3990
   delete-key test plus USB 3 enumeration in the same RAM boot, if and only if
   he explicitly widens the approval. The current approval is for the WLAN test
   alone and Aurel's handoff says not to fold other lanes in.
4. **ADSP enable + SLIMbus node** — host-buildable.
5. **WCD934x + sound card** — host-buildable to probe; needs device to hear.
6. **PMI8998 VBUS regulator in `qcom_smbx`** — the real unlock for OTG.
7. **PMI8998 TCPM in `qcom_smbx`** — automatic role detection.
8. **msm8998 CAMSS resources**, then sensors — long tail.

Steps 1, 2, 4 are all host-side and can proceed with no device risk while the
WLAN test stays held.

## 5. The sealed WCN3990 kernel cannot boot joan — wrong config

Found by taking the RAM boot after Lance lifted the hold. Recording it here
because it invalidates the premise of the sealed handoff and because the
failure shape generalises.

### Symptom chain **[CONFIRMED on device]**

1. RAM boot succeeded; initramfs banner confirmed
   `Kernel: 7.2.0-rc2-g834154d6b082`.
2. pmOS initramfs: `Trying to mount subpartitions for 10 seconds...` →
   `ERROR: failed to mount subpartitions!` → debug shell.
3. In the debug shell, `ls /dev/mmcblk*` → **no such file**. Every UFS LUN
   (`sda`–`sdg`) is present; there is no MMC block device at all.
4. `dmesg`:
   `sdhci_msm c0a4900.mmc: Got CD GPIO` then
   `platform c0a4900.mmc: deferred probe pending: sdhci_msm:`
   `dev_pm_opp_of_find_icc_paths: Unable to get path0`, plus
   `sync_state() pending due to 1660000/1700000/1740000.interconnect`.

### Root cause

`# CONFIG_INTERCONNECT_QCOM_MSM8998 is not set` in the config the sealed
kernel was built from. With no ICC provider, `sdhc2`'s
`interconnects = <&a2noc MAS_SDCC_2 &bimc SLV_EBI>` can never resolve, the SD
controller defers forever, the SD-hosted pmOS rootfs is invisible, and no
module ever loads.

Every other build under `/data/buildcache/kbuild/` — ~25 of them, every boot
that has ever worked — has `CONFIG_INTERCONNECT_QCOM_MSM8998=y`. The sealed
build is the sole outlier. It was built from
`lg-v30-pmos-prealpha/.../config-lge-joan.aarch64`, a config first committed
**the same day** ("build: add reproducible LG V30 pre-alpha workspace") that
had never booted anything.

196 config symbols differ from the known-good lineage; 28 options enabled in
known-good are absent from the sealed build, including the whole WCN3990
prerequisite stack as `=m` where known-good has `=y`: `QCOM_QMI_HELPERS`,
`QRTR`, `QRTR_SMD`, `QCOM_RMTFS_MEM`, `QCOM_Q6V5_MSS`, `QCOM_RPROC_COMMON`,
`RPMSG_QCOM_GLINK_SMEM`. Those alone would not be fatal (modules come from the
rootfs) — but only if the rootfs can be reached, which the ICC fault prevents.

**Aurel's three delete-key commits are fine.** The source was never the
problem; the build input was.

### Why the verification ceremony missed it

The sealed handoff records `input_config_sha256`, `effective_config_sha256`,
compiler version, artifact SHAs, an evidence bank, and a signed commit stack.
All of that proves the build is **reproducible**. None of it proves the config
is **fit**. The wrong input was hashed faithfully and thereby made to look
qualified.

The missing check is one line: diff the build config against a config that has
actually booted the device. Recommend adding that as a gate before any future
"sealed" build is offered for a device test.

A related note in the sealed handoff — "`CONFIG_NF_TABLES` absent,
`CONFIG_IP_NF_IPTABLES=m`" — is **not** the same root cause and is itself
slightly off: the overlay config has `NF_TABLES=m`, while known-good does not
set it at all. Different issue; do not fold the two together.

### Fix

Rebuild the identical source commit `834154d6b082` against the known-good
config lineage rather than the overlay config. Tracked as task #9: the overlay
config will keep producing unbootable kernels until it is corrected or dropped
as the build input.

---

## Stop conditions carried forward

Unchanged from Aurel's handoff: no packaging, no staging, no `fastboot boot`,
no flashing, without a fresh explicit approval naming the image SHA. Sealed
kernel remains `834154d6b082` / `Image.gz`
`7336888c9c18ae007a935091b1c1614e8c79dac7289e4260b3db854507ad4551`.

Assisted-by: Claude-Code:claude-opus-5
Date: 2026-08-15
