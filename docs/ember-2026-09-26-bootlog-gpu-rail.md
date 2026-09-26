# Boot-log fixes, GPU rail, build-speed findings (2026-09-26, Ember)

Written-by: Ember (agent-ember)
Agent-harness: Claude-Code:claude-opus-5-5
Device: LG V30 US998 `LGUS9986e606d55`, MSM8998 v2.1, CPU speed bin 2
Picks up: [fulgor-2026-09-26-pmaports-handoff.md](fulgor-2026-09-26-pmaports-handoff.md)

Status markers: **verified** = observed on the phone; **build-verified** =
compiles, DTB decompiles as intended, not booted yet.

## The codeload 429 is no longer a blocker

GitHub's `/archive/<sha>.tar.gz` is byte-identical to

    git archive --format=tar --prefix=linux-lg-v30-joan-<sha>/ <sha> | gzip -n

Verified twice: `db210e9` (against the real Sep-25 codeload download) and
`8d7f34b` (266048754 bytes, sha512 `6ac9332f…`). When codeload rate-limits the
family WAN, drop the local reproduction into pmbootstrap `cache_distfiles/` and
run `pmbootstrap checksum`. Do not use `gh api …/tarball/`: different prefix,
different bytes. The commit still has to be pushed, because users fetch it.

## pmaports

- `b007cff07c` device-lge-joan: drop joan-input-boost (pkgrel 16). It never ran:
  `os.read()` on an `O_NONBLOCK` evdev fd raised `BlockingIOError` on the first
  loop, and `Restart=always` relaunched it every 5 s for the whole uptime. No
  pmaports device ships an input-boost service. Mainline answer: schedutil +
  OSM fast_switch; uclamp if touch latency ever measures badly.
- `kconfig check` passes on r27. `BPF_LSM`, `bpf` in `CONFIG_LSM` and BTF are
  already set there; the `bpf-restrict-fs` warning came from the **bench**
  config (`joan-lct-dvfs`), not the pmaports one. Triage boot logs on the
  default install, not the bench kernel.

## Kernel branch `joan/bootlog-fixes` (from `8d7f34b066e9`, local, not pushed)

1. `f32b02481762` SoundWire IRQ (build-verified). `1d8fa25685b2` moved swm to
   hwirq 8 on the belief that the wcd934x regmap-irq domain has nine slots.
   `WCD934X_REGMAP_IRQ_REG()` is a designated initializer, so the table has 21
   entries and SoundWire is hwirq 20 (as sdm845). hwirq 8 is `MBHC_SW_DET`: the
   two drivers raced for one Linux irq and SoundWire failed with -EBUSY. The
   WCD SoundWire master only serves WSA881x amps, and LG disables all four on
   joan (speaker = TFA9890 on I2C), so the node is now irq 20 **and disabled**;
   mfd-core skips a disabled cell without error.
2. `32f74fd8507c` / `2f3d58f548b2` / `05f76fea3984` A540 VDD_GFX (build-verified).
   See next section.

## GPU rail: the old table was one fast part's CPR floor

Evidence: [evidence/2026-09-26-gpu/gfx-cpr-fuses.txt](evidence/2026-09-26-gpu/gfx-cpr-fuses.txt).

- Downstream GFX CPR4 (`cpr3-mmss-regulator.c`, `qcom,cpr4-msm8998-v2-mmss-regulator`)
  computes a per-part open-loop voltage from qfprom row 65 and uses it as each
  corner's **ceiling** (`qcom,cpr-scaled-open-loop-voltage-as-ceiling`).
  Closed loop only lowers from there, to at most
  `qcom,cpr-floor-to-ceiling-max-range` (40/50 mV) below.
- This part: fusing rev 2, fuses 8/5/8/6 → open-loop 656/668/680/744/832/896/956/984 mV
  (180..710 MHz). Open-loop minus 40/50 mV reproduces the stock-measured
  628..936 mV curve exactly at 6/7 corners. So the joan DT table was the stock
  CPR **floor** on a fast part; the fuse spans ±150 mV, so another V30 could be
  fused ~140 mV higher than that table at 710 MHz.
- `a540_gfx_rail.c` recomputes the open-loop voltages at probe (same arithmetic:
  rev tables, sign-magnitude fuse, +60 mV FC0, monotonic, interpolation, 4 mV
  round-up, floor/ceiling, partial-binning and force-highest fuses). The DT
  fallback is now the stock rev≥1 ceilings (724..1088 mV), safe on any part.
  Cost versus stock on this phone: about +40–48 mV per corner until a GFX
  closed-loop port exists.
- **MEM-ACC was never programmed.** TCSR `0x1fcf004` bit 0 must be 1 at corners
  1–3 (≤342 MHz) and 0 above. Downstream sets the low-voltage value before the
  rail drops and the high-voltage value after it rises. It read **0** with the
  GPU at 257 MHz. Now a `config_clks` callback writes it, and the OPP core's
  regulator ordering gives downstream's sequence.
- There is no GPU speed-bin split on v2 silicon: a single pwrlevel table, 710 MHz on
  every part.

## LG per-device CPR margins (not ported yet)

LG's `lge_cpr_manager.c` reads signed mV offsets for APC0/APC1/GFX from IMEM
`0x146BFE9C` + 6/7/8 (written by LG's bootloader) and adds them to open-loop,
floor and ceiling in both the CPU and GFX CPR code. On this phone all three are
**0** (read 2026-09-26 on pmOS). Mainline msm8998 has no IMEM node; honoring
the margins needs `qcom,msm8998-imem` plus a small hook in cpr3 and
a540_gfx_rail. Low risk while they read 0, but other units may differ.

## CPU items found this session

- Gold single-core boost: LG's bin-2 table pairs 4-core (`0x0404…`) and 1-core
  (`0x0401…`) rows on the same voltage corner, up to 2457.6 MHz. Our OSM driver
  writes core count 4 into every row (qcom-cpufreq-osm.c:591). Needs 1-core
  rows plus the OSM core-count DCVS FSM; hardware testing required.
- Speed bins: OSM refuses bins other than 2/3 (safe, but gold then sits at LK's
  300 MHz). LG's DT has perfcl tables for bins 0–3 and one pwrcl table;
  CPRh corners per bin `<32 26 30 31>`. cpr3.c reads the bin fuse but uses
  bin-2 data for all parts.
- The bench phone's governor was `performance` (tuned-ppd bench state). The pmaports
  config defaults to schedutil.

## Build speed

- `/data` (pmbootstrap work dir, all chroots, ccache) is a Seagate
  ST31000524AS **spinning HDD** under btrfs + dm-crypt. A kernel build there
  is I/O-bound (compilers mostly in D state). The same `drivers/gpu/drm/msm/`
  subtree built in tmpfs in 44 s. `/home` (NVMe) has only 13 MiB unallocated
  on btrfs.
- The r27 config is arm64-defconfig-shaped: ~40 SoC families (Tegra, Renesas,
  Rockchip, Apple, mlx5…). Trimming to `ARCH_QCOM` (what pmOS's own
  sdm845 kernel does) drops 1461 → 971 modules and 3388 → 2353 built-ins with
  no Qualcomm symbol lost (checked by diff). Also DWARF5 like sdm845. Candidate config:
  scratchpad `ktrim/.config`. **Gate:** compare against the r27 boot's
  bound drivers and loaded modules before committing.

## Next

1. r27: finish build → apk install on SD → initramfs → RAM boot → verify
   (release string, systemd, schedutil, DVFS, boot-log triage on the default install).
2. Bench-boot `joan/bootlog-fixes` + trimmed config (`-joan-bl`): check the
   `GFX open-loop mV` line, `/sys/kernel/debug/opp`, MEM-ACC readback at
   257 vs 710 MHz, soundwire gone, driver list vs r27.
3. Push `joan/bootlog-fixes` after (2), then pin pmaports.
4. DP alt mode: resume [handoff-2026-09-25-dp-altmode.md](handoff-2026-09-25-dp-altmode.md).

## Parallel msm8998 7.2 work: porthole-dev/pmaports

`porthole-dev/pmaports` → `device/testing/linux-postmarketos-qcom-msm8998-7.2`
carries 262 patches on the same 7.2 base, mostly for the Pixel 2 (wahoo) by
Giuseppe Maggio (jertlok). Relevant to joan:

- 0211: the same GPU finding. The old A540 OPP table sat under the downstream
  GFX CPR4 ceilings, and A540 hung at 710 MHz with the SoC above 70 °C. He uses the
  global ceilings (724..1088 mV) on every part. Ours uses each part's fused
  open-loop voltage, which is the most stock ever applies to that part:
  downstream MSM8998 v2 GFX CPR has no temperature or core-count voltage
  adjustment (checked `msm8998-v2.dtsi` + `msm8998-regulator.dtsi`). Our fallback
  is the same ceiling table.
- 0251: A540 on-die limiter (GPMU) enabled, five voltage levels (six hangs the
  linux-firmware GPMU).
- 0076-0104, 0114: wcd934x / SLIMbus fixes. Joan audio currently shows SLIMbus
  QMI timeouts and no backend DAIs, so review these before debugging audio from scratch.
- 0071-0119: an alternative CPRh/OSM implementation (in cpufreq-hw), with
  notes on the APM threshold, droop FSMs and ACD busy-poll.
- 0249: LMh limiter thermal support; 0241: spmi-adc-tm5 IIO fix.

## Thermal: LG's stock policy (evidence/2026-09-26-thermal/)

`thermal-engine-8998.conf` (TheMuppets proprietary_vendor_lge_joan-common,
lineage-22.2) is the stock userspace policy:

- Junction: step-wise at 85 °C (clear 80) per CPU cluster, GPU 85 (clear 65),
  POP mem 85 → gold. Mainline has passive trips at **75 °C**, which throttles about 10 °C
  earlier than stock.
- Skin, VTS = 0.37·xo_therm + 0.48·bd_therm_2 + 3.83 °C (LG kernel `lge,vts`):
  gold 1958.4 MHz @37, 1728 @38.5 (skin_ap), 1056 @41, 729.6 @44, silver 1555.2 @46;
  GPU 670 MHz @38, 515 @39, 414 @41, 342 @42.5.
- Charger: skin_pmic 40/42/45 °C → 1.5/0.8/0.6 A.
- Kernel msm_thermal (LG DT): gold 1.536 GHz at 95 °C; reset 115 °C.

Mainline supports one sensor per zone (`coefficients` is only slope/offset), so
VTS needs a small virtual sensor: an IIO weighted sum registered as its own
thermal zone. Mainline currently has no skin zone at all.

## r27 default install (verified 2026-09-26)

- Built with pmbootstrap (45 min, almost all HDD wait). Installed with `apk add` on the
  bench SD. mkinitfs was **skipped**: the bench SD carries `/in-pmbootstrap`
  (since 2026-09-06), so no kernel upgrade there has regenerated initramfs/boot.img
  for three weeks. A user install is clean (pmbootstrap deletes the marker before
  copying). `sudo mkinitfs` by hand → device-generated boot.img → RAM boot.
- Boots: `7.2.0-rc2` (plain; `LOCALVERSION=""` + AUTO on a tarball build),
  systemd `running`, 0 failed. Gold 2357 MHz, silver 1893 MHz, LMh 1120/1136 mV.
  Evidence: `evidence/2026-09-26-r27/`.
- The governor was `performance` because the bench's TuneD was manually set to
  `throughput-performance`. pmOS TuneD `balanced` asks for `schedutil` first, so a user install
  gets schedutil.
- `bpf-restrict-fs` still fails on r27: `CONFIG_FUNCTION_TRACER` is off, so BPF
  LSM programs can't attach (arm64 uses ftrace trampolines). Only `capability,bpf`
  LSMs are active.
- `/` on the bench SD is `1023:1023 0555`, which is Android's media_rw. Lineage's vold shows four PUBLIC
  volumes with ext4-style UUIDs, so it most likely mounts the pmOS card and chowns its root.
  systemd-tmpfiles then refuses "unsafe path transitions". Verify on the fresh card after
  one Lineage boot; this matters for the README's dual-boot SD flow.
- Firefox + YouTube crash: A540 GPU VM based at 2^48 (`GENMASK_ULL(48,0)` keeps
  bit 48). Faults show `ttbr0=0 iova=0x0001_0000_0bxx_xxxx`, then CP opcode errors and
  hangcheck, and phoc SEGVs. Fixed on `joan/bootlog-fixes` with porthole-dev 0030 + 0031 (+0168,
  0176, 0067). Not the voltage table.
- No hardware video decode: the Venus node was disabled and no firmware was shipped. Now fixed
  (blobs eb14f12, firmware-lge-joan r9, DT on the branch).

## Firmware

- Venus and SLPI v2 added per-variant after a whole-set comparison (Venus 4/6
  identical, SLPI 2/15, so nothing can be shared). No existing image is shareable either.
- The package pin had never moved past the blobs repo's first commit, so the WCN3990 board
  data from Sep 7 now ships too.
- SLPI needs a 15 MiB region (joan reserves 2 MiB); Deck #162.

## FM

WCN3990 "Helium" FM over BT HCI, driven by userspace on stock (no kernel driver in
LG's tree). Transmit: the protocol header has TX opcodes (legacy from iris chips),
but the Helium HAL implements none and stock never shipped TX. Test once RX exists; Deck #163.

## Fresh `pmbootstrap install` (device lge-joan, phosh, --no-split)

Succeeded in about 7 min using local packages. Written to the SD from Lineage (adb push the
.zst, then `zstd -dc | dd` on the phone at 19 MB/s; streaming through `adb exec-in` ran
at 1.7 MB/s). Installer warning: "Firewall is enabled, but may not work (couldn't
determine if kernel supports nftables)". README step 2 (`pmbootstrap install`)
yields split images for fastboot devices, so the SD flow needs `--sdcard`/`--no-split`.

## Fresh default install (pmbootstrap install → SD → RAM boot), 2026-09-26

First try: unbootable. deviceinfo sets `rootfs_image_sector_size=4096` (correct for
UFS), so `pmbootstrap install --no-split` writes a GPT at byte 4096. The SD has
512-byte sectors, so no partitions appeared → initramfs "failed to mount
subpartitions" → telnet debug shell. Fix: SD images need `--sector-size 512`
(README a5df41ca25); `--sdcard` is unaffected.

Second try (512): sshd 25 s after fastboot, systemd `running`, 0 failed units,
`/` root:root, schedutil via stock TuneD balanced (auto), phosh/greetd,
PipeWire+WirePlumber, callaudiod, feedbackd running. Evidence:
`evidence/2026-09-26-fresh-install/`.

- The root fs was not grown: `resize2fs` refused ("Please run 'e2fsck -f' first"). **Upstream pmOS
  bug** since 8e2ce06af5 (MR 5844, dropped `resize2fs -f`): `e2fsck -p` leaves a
  clean fs's last-check time older than pmbootstrap's install mount. It reproduces on any host.
  Fixed in our pmaports (61cba4999e, pkgrel 2, tests 6/6): on refusal, `e2fsck -f -p` then
  retry. Upstream main is unchanged, so this should go upstream. The bench was grown online (2.6 s, 177 GB).
- Userspace warnings on the default install: bpf-restrict-fs, uhid/uinput and bluetoothd
  RFCOMM "Protocol not supported" are all fixed by the community config on
  `joan/bootlog-fixes`. `usb-moded-notify` races the notification server
  (upstream package ordering). **callaudiod: "No suitable card found"**: joan's UCM
  has only `HiFi`, no `Voice Call` verb, so CS call audio has no route. Needs
  q6voice (now enabled on the bench), the DT voice services and routing (porthole 0159-0175),
  plus a UCM verb.

## Jev triage of porthole-dev (260 patches, 2 m 50 s, 0 errors)

`scratchpad porthole_triage.py`: code checks apply status against our tree; Jev
(jev-latest) answers "relevant to the V30 port" (noul), subsystem (choice) and
"fixes a crash/hang/reset" (noul). 188 relevant, 80 crash fixes, 178 relevant and
not in our tree. Subsystem labels are sometimes off (Venus filed under audio/camera);
relevance and crash judgments read right. Output: `evidence/2026-09-26-porthole-triage.json`.
Imported so far on `joan/bootlog-fixes`: 0030 0031 0168 0176 0067 0210 0204 0251
0001 0032 0121 0205. Venus needs ~15 of them (0185-0199…), so the Venus DT enable was
reverted until those are ported.
