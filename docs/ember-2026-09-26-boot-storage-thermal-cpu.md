# Boot, storage, thermal and CPU DVFS findings (2026-09-25/26)

Written-by: Ember (agent-ember)
Agent-harness: Claude-Code:claude-opus-5-5
Device: LG V30 US998 (`LGUS9986e606d55`), pmOS on microSD, RAM-booted with `fastboot boot`
Picks up: [aurel-handoff-2026-09-25-to-ember-f08d8c5-boot.md](aurel-handoff-2026-09-25-to-ember-f08d8c5-boot.md)

Every claim below was measured on the phone unless marked otherwise.

## Summary

| Area | Before | After | Where |
|---|---|---|---|
| Boot to userspace | debug shell, then blank screen | systemd `running`, 0 failed units | cmdline + kernel |
| Display | no DRM card | `card0` at 2.1 s, DSI-1 lit, DP-1 registered | kernel + pmaports config |
| SD sequential write | 0.09 MB/s | 21-27 MB/s | kernel `1dd4e409` |
| SD sequential read | 5.6 MB/s | 70-79 MB/s | kernel `1dd4e409` |
| SD Auto-CMD/cmd timeouts | tens per minute | 0 | kernel `d5cc96a1` |
| Boot WARN splat (clkref) | every boot | gone | kernel `38300165` |
| CPU cpufreq policies | 8 single-CPU | 2 (CPUs 0-3, 4-7) | kernel `db210e9f` |
| CPU cooling devices | none | `cpufreq-cpu0`, `cpufreq-cpu4` | kernel `db210e9f` |
| dmesg err+warn lines | 109 | 66-71 | several |
| Gold cluster real clock | ~150 MHz | **not fixed yet** (see CPU DVFS) | WIP branch |

## Boot: why Aurel's images went blank

1. `pmos_root=LABEL=pmOS_root` on the cmdline. The initramfs treats
   `pmos_root` as a literal path (`[ -e "LABEL=pmOS_root" ]`) and
   deliberately does not fall back to the label, so `wait_root_partition`
   ran into `fail_halt_boot`. That is where the "debug shell" came from
   (the image has no `/hooks`), and `pmos_continue_boot` then sat in
   "Looping forever". The p2 superblock confirmed no rw mount on any of those
   boots. Fix: drop the argument; the default label lookup works. The
   deviceinfo cmdline never had it.
2. `phy-qcom-qmp-usbc` never registered a DRM aux bridge, so msm-dp deferred
   forever and held the whole MDSS component aggregate (DPU, DSI, panel).
   Fixed in kernel `36ba6e40`.
3. A git-tree build is named `7.2.0-rc2-g<sha>` (`LOCALVERSION_AUTO`), while the
   rootfs only had `/lib/modules/7.2.0-rc2`. A pmbootstrap package build uses
   a tarball and is named `7.2.0-rc2`, so users do not hit this; manual test
   images need matching modules installed.

pmaports now builds `TYPEC_TCPM`, `TYPEC_QCOM_PMIC`, `REGULATOR_QCOM_USB_VBUS`
and `DRM_AUX_HPD_BRIDGE` in (`=y`). DP gets its HPD bridge from the PMIC Type-C
port, and as modules they only loaded from the rootfs, so DRM bound at about
50 s, after greetd. Built in, it binds at 2.1 s.

## SD card

Card: SanDisk 200 GB (manfid 0x03, OEM "SD"), A1/U1/Class 10, 11/2020.
Bus: SDR104, 200 MHz, 4-bit, 1.8 V, on both mainline and Lineage. That is
LG's own maximum (`qcom,clk-rates` tops out at 200 MHz) and the UHS-I ceiling.
LG did not down-tune it.

- **Mainline bug (`1dd4e409`)**: the errata-i2493 retry path sets
  `MQRQ_XFER_SINGLE_BLOCK` in the blk-mq PDU and never clears it. After a few
  errors, every request on those tags went out as 512-byte `CMD24`. An 8 s trace
  showed 2388 CMD24 and 0 CMD25. Fixed by clearing `->flags` next to `->retries`
  in `mmc_mq_queue_rq()`. Upstream has no fix yet.
- **sdhci-msm (`d5cc96a1`)**: MSM8998 loses the SDR DLL config when runtime PM
  gates the core clock. An A-B-A test (6 rounds of rw + idle) gave runtime PM
  auto +31 errors, on +0, auto +10. It now restores the DLL like SDM845.
- Lineage 4.4 baseline for the same card: read 20.1 MB/s, write 19.5 MB/s,
  4K 43.6 IOPS. Mainline is now faster.

## UFS (internal storage)

Samsung KLUDG4U1EA-B0C1, 128 GB, UFS 2.1. It probes fine, clock scaling moves
G1 to G3 x2 at 200 MHz, and there are 0 PA/DL errors. But reads reach only
32-62 MB/s against 219 MB/s on Lineage. Four readers get the same total as one,
so the limit is bandwidth.

- `5710765` added the missing `ufs-ddr`/`cpu-ufs` interconnect paths.
- With the NoCs held at boot max (IPA blacklisted, so `sync_state` never fires)
  UFS reads a steady 79-84 MB/s. The post-sync_state vote shape matters:
  downstream votes **ab 4194304 KBps** (average) for HS-G3 RB x2, while mainline
  ufs-qcom votes avg 0 / peak 1492582.
- A second limiter still caps UFS near 82 MB/s even at fabric max.
- The a1noc/a2noc descriptors use msm8996's branch clocks, but msm8998's are
  rate clocks (`clock-gcc-8998.c`). The fix is on the local branch
  `ember/ufs-noc-wip` and is not pushed: it boots fine but made no measurable
  UFS difference.

The Lineage 4.4 kernel is not affected by the mmc bug: `disable_multi` is a
per-call local there.

## Boot-log triage

Unique kernel warnings were classified with Jev (TypeSafe `noul`). The local
`minicpm5:2b` failed the positive control and returned "no" even for
`phy init failed -16`. Every item was then checked by hand.

Fixed:

- `gcc_rx1_usb2_clkref_clk status stuck at 'on'` WARN (`38300165`,
  `BRANCH_HALT_VOTED`).
- DP PHY: msm-dp ignores `phy_init()` and tried link training at about 3 s
  and 99 s with only a PC on USB-C. The DP ops now refuse to touch the SerDes
  unless DP is initialised (`5371fb35`). The warnings remain; the spurious HPD
  still needs a real DP sink to chase.
- Stale cmdline options `q6core.skip_versions`, `slim_qcom_ngd_ctrl.slim_dbg`
  removed (pmaports `f94d9b8f82`).
- `joan-imsd.service` had its `StartLimit*` keys in `[Service]`; they now sit in
  `[Unit]`.

Open:

- Audio: MBHC IRQ 159 clashes with SoundWire, SLIMbus QMI timeout, no backend
  DAIs.
- Wi-Fi SMMU faults (SID 0x1900, iova 0).
- Missing supplies (Wi-Fi ch1, camss `vdd_sec`, TFA9890 `vddd`).
- `stmfts error code`, BT reassembly (-84), random Wi-Fi MAC.

## Thermal and CPU

- `db210e9f`: both CPU OPP tables are `opp-shared`, every CPU has `#cooling-cells`,
  and each `cpuN-thermal` passive trip (75 C) maps to its cluster's cpufreq
  cooling device. Before this, only the GPU could be throttled.
- tuned-ppd on the bench was set to `performance` (the governor was forced to
  performance). That is bench state; the pmOS default is `balanced`.

### CPU DVFS does not work on mainline (major)

The real clock was measured with a static dependent-add loop, since mainline has
no PMU node yet:

| | Lineage (downstream OSM+CPRh) | mainline, clk-osm-8998 | mainline, OSM driver blocked |
|---|---|---|---|
| silver | ~1740-1773 MHz, scaling | ~1549 MHz, fixed | ~1460-1545 MHz |
| gold | **~2375 MHz** | **~148 MHz, fixed** | ~297 MHz |

Requested frequencies have no effect (sweep 300 to 2476.8 MHz). `clk-osm-8998`
only writes the LUT and enables the OSM. Downstream also sets up the sequencer
FSMs, cycle counters, core-count/LLM policies, MEM-ACC/APM crossovers and ACD,
and takes open-loop voltages from CPRh. LK leaves gold on the 300 MHz safe
clock. The scheduler therefore sends heavy work to cores that are 5-10x slower
than the little ones.

**Speed bin**: qfprom `0x130` = `0x5002005e`, perfcl bin `(>>29)&7` = **2**.
Lineage's own log agrees (`cprh ... speed bin = 2`). Bin 2's qualified gold
maximum is 2361.6 MHz all-core and 2457.6 MHz single-core boost. That boost is
LG's "2.45 GHz", so LG did not cap anything. Our `clk-osm-8998` always loads
bin 0's table and advertises 2476.8 MHz all-core, which is beyond this chip's
rating.

**In progress** (local branch `joan/cpu-dvfs-cprh`, not pushed, not yet booted):

- CPR3/CPR4/CPRh v15 (AngeloGioacchino Del Regno / Konrad Dybcio) rebased onto
  7.2-rc2.
- New `drivers/cpufreq/qcom-cpufreq-osm.c`, ported from AngeloGioacchino's v6
  "Implement full OSM programming" to the 7.2 OPP/genpd APIs. It takes over only
  on speed bins 2 and 3, the bins the OPP/CPRh tables describe.
- DT: CPRh fuses, levels and controller, plus bin-2 CPU OPPs carrying the OSM
  LUT words (`qcom,pll-override`, `qcom,spare-data`, `qcom,pll-div`) decoded from
  downstream `msm8998-v2.dtsi`.
- OSM regions: `osm-domain0/1` at `0x179c0000`/`0x179c2000`, `freq-domainN` at
  +0x1000, `osm-acd0/1` at `0x17914800`/`0x17814800`. Downstream never sets
  `qcom,osm-pll-setup` on msm8998, so the OSM drives the cluster PLLs itself.

## Camera

Sensors: IMX351 (main, CCI0/CSIPHY0), S5K3M3 (wide, CCI1/CSIPHY1) and Hi-553
(front, i2c 8-0040, CSIPHY2). `CONFIG_VIDEO_IMX351` was not enabled. Enabling
it shows `camss_ahb_clk status stuck at 'off'` on CCI runtime resume, and IMX351
then fails its 24 MHz MCLK check. Loaded at boot together with the rest, it hangs
the SoC. It is kept out of pmaports until that is fixed.

## FM radio

It is the WCN3990's FM receiver. Control is HCI packet types 0x11/0x14 on the
Bluetooth UART, OGF 0x13-0x17 (reference `vendor/qcom/opensource/fm-commonsys`
`helium/`). Audio uses btfm SLIMbus. Mainline `hci_qca` drops these packet types,
so the plan is an FM side channel in `hci_qca` plus a V4L2 radio driver, with
audio after SLIMbus. Bluetooth itself works on mainline.

## Repositories

- Kernel `joan/latest-clean-test` = `db210e9ffc91`; `master` gained the two mmc
  fixes and the clkref fix as cherry-picks. The cooling DT does not apply to
  master's older lineage.
- pmaports `joan/readme-build-guide` = `227f438165` (linux-lge-joan r26). Every
  bump was built with pmbootstrap, installed with apk on the bench, and booted
  from the on-device `boot.img`.
- Journal: `~/.hermes/journal/joan-f08d8c5-boot-2026-09-25.md`.
