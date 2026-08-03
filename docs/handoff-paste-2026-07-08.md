# LG V30 (joan) mainline port — handoff + primer (2026-07-08)

Assisted-by: Claude-Code:claude-fable-5

## 30-second status

Porting mainline Linux (v7.2-rc2) to the LG V30 US998 (joan, msm8998). Test
boots are RAM-only `fastboot boot` (never flashed; LineageOS on eMMC is the
daily driver + crash fallback). The kernel boots fully and runs, but **a
TrustZone-side reset pulls PS_HOLD ~30–45 s in, before USB comes up.**

- **One confirmed fix:** `anoc1_smmu` skip-reset (details below) — eliminated
  a TZ "Config NoC" fault. The residual fault is TZ **"MM NoC"**
  (`bootreasoncode 0x6D630306`, reported generically as `0x20` after the fix).
- **The big reframe (from the edk2 UEFI, below):** the reset is caused by
  something **our kernel actively does** during SoC init — NOT a missing
  keepalive/handshake. So the fix is *subtraction*, and the two live fronts
  are: **(A) find the remaining aggressive init**, and **(B) the edk2 UEFI**
  (both an escape hatch and a reference).

## The confirmed fix (keep this)

Mainline's arm-smmu-v2 driver runs a full global reset on every SMMU at
probe. `anoc1_smmu` (`iommu@1680000`) is TZ-owned (downstream marks it
`qcom,skip-init`), and resetting it from the non-secure side triggers the TZ
Config-NoC reset. Fix = skip `arm_smmu_device_reset()` for it. Currently a
debug patch gated on a DT bool `debug-skip-reset` (patch:
`out/k030-skip-smmu-reset-debug.patch`, applied to
`drivers/iommu/arm/arm-smmu/arm-smmu.c`; DT node `&anoc1_smmu`). Not yet
upstream-shaped (needs a real `qcom,skip-init`-equivalent binding).

**Confirmed clean baseline for all tests:** full untouched joan DTS + the
anoc1 skip-reset + plain default cmdline (`androidboot.hardware=joan panic=0
ignore_loglevel`). The `clk_ignore_unused pd_ignore_unused` flags earlier
sessions used are NOT load-bearing (proven K032).

## PRIMER A — the "aggressive init" hunt (Finding 1)

**Why:** the edk2 UEFI (see B) does essentially ZERO SoC init — no clock,
SMMU, NoC, SCM, or hardware-watchdog driver — leaves the SoC exactly as XBL
configured it, pets nothing, does no secure handshake, and **survives to boot
Windows** (far past our 30 s). Since even a do-nothing Linux init (K022) still
resets, the reset is provoked by an *action* our kernel takes that the passive
UEFI doesn't. This validated the subtraction approach and casts doubt on the
"add a TZ/SCM handshake" idea (K040 was negative and inconclusive).

**Already eliminated — do NOT re-test these as the cause:**
- anoc1 SMMU reset — FIXED (K030). All 5 SMMUs' resets — no additional effect
  (K031). Clock-disable sweep / `clk_ignore_unused` — irrelevant (K032, K036).
- Board peripherals (usb/ufs/wifi/regulators) — not it (K033). APSS watchdog,
  petted or disabled or timeout-changed — not it (K024/K034/K037). MMCC bring-up
  — no change (K039). RPM is *required scaffolding* — removing it regresses to
  Config-NoC (K028/K029), so keep it. Bootloader display — not it (K038).
  pinctrl-msm/TLMM and QUP/GENI/BLSP — cleared in source. Full msm8998
  interconnect provider — scoped, deprioritized (QoS isn't fault-gating and no
  MM master is active in bring-up).

**What's left (candidates for the aggressive action):** something in the
core init the UEFI doesn't do — most likely a driver *probe* (not the sweep)
that writes to a TZ-watched block. Suspects: the GCC clock controller's probe
(any block-control-reset / BCR it asserts), genpd, the arm-smmu-v2 driver's
*non-reset* actions (SMR/S2CR programming, context-bank setup) on the SMMUs
that still probe (anoc1/anoc2), or an early qcom_scm/rpmh interaction.

**Method:** bisect by *suppression*, using the passive UEFI as the "minimal
that works" reference. Cheap knobs, no rebuild:
- `initcall_blacklist=<fn1>,<fn2>` on the cmdline disables specific driver
  init functions — blacklist suspect probes (e.g. the arm-smmu, gcc, or scm
  init) and see if the reset stops.
- Or disable suspect subsystems via `.config` and rebuild.
- Classify each boot with `scripts/tethered-test.sh <img> 150` (below): early
  LOS return (~30–45 s) = still resets; survives to ~90 s = fixed.

**The catch:** this is *blind* (survive/reset binary; the fault detail lives
in the secure TZ log we can't read — ramoops is scrubbed, /dev/mem is absent,
on-screen console failed — see below). So it's slow. Real observability (B or
a UART cable) would make it fast.

## PRIMER B — the edk2 UEFI (escape hatch + reference)

`github.com/edk2-porting/edk2-msm8998` (Renegade Project; also
`lumingyu0423/edk2-MSM8998`) is an open-source EDK2 UEFI that **supports joan**
and boots Windows. It's loaded by LG's bootloader the same way our kernel is:
disguised as a Linux kernel (magic header + appended DTB) and launched via
`fastboot boot` — RAM-only, non-destructive, same position as our tests.

**Why it matters twice over:**
1. It boots Windows → proves the reset is beatable from our exact boot spot.
2. It has its own **working on-screen console** (its `SimpleFbDxe` displays
   because LG's bootloader keeps the panel live early — unlike our late Linux
   fbcon, which finds the command-mode panel already frozen; that's why the
   K041 on-screen-console attempt showed nothing).

**How to get/boot it (device work — be present, one fastboot client):**
1. Easiest: check the repo's GitHub **Releases** for a prebuilt `boot_joan.img`
   (or a joan `.img`). If present, download it.
2. Otherwise build: `git clone --recurse-submodules` the repo (the shallow
   clone at `~/vibe-coding-projects/coding/edk2-msm8998` has NO submodules —
   building needs `Common/edk2` + `Common/edk2-platforms` + the EDK2 build
   toolchain), then `./build.sh` targeting joan (see its README).
3. Boot it (same discipline as our kernel tests): `adb reboot bootloader`,
   then one `sudo -n fastboot boot boot_joan.img`. RAM-only, nothing flashed.

**What to look for / next steps with it:**
- Does a UEFI logo / shell appear on screen, and does it **survive past 30 s**
  without resetting? (It should — that's the existence proof + an observable
  environment.)
- Does it offer a way to boot Linux (a boot menu / EFI shell / GRUB)? If it can
  chainload a mainline Linux EFI-stub kernel, boot mainline *from* it: the SoC
  is already sane and the display already live, which could (a) sidestep the
  reset and (b) give inherited on-screen output. This is uncertain (the project
  self-describes as "terribly broken", Windows-focused) but it's the highest-
  upside software path.
- Reference use: read its init source for what it does/doesn't do vs our kernel
  — it's small, focused C, far more tractable than the downstream Android kernel.

## Observability status (why the above is hard)

No console on joan: ramoops region is scrubbed by LG's boot chain; `/dev/mem`
is absent on the LOS build (`CONFIG_DEVMEM` off); the DSI **command-mode DSC
panel** freezes on the XBL frame before Linux's framebuffer console starts, so
simplefb/fbcon shows nothing (K041, confirmed). The reset detail (which
master/address) is in the **secure TZ log**, unreadable from the non-secure
side. Reliable observability options: a **1.8 V USB-to-UART cable** on joan's
`blsp2_uart1` (@0xc1b0000; needs a 1.8 V FT232/CP2102 + USB-C SBU access or
test pads — under-documented for the V30, likely internal pads found via
multimeter: TX sits ~0.9 V early then swings 1.8/0 V), or the **edk2 UEFI's own
console** (B).

## Key state, tools, rules

- **Repos:** kernel `~/vibe-coding-projects/coding/linux-mainline-v30`
  (branch `joan/latest-clean-test`, dirty with only the anoc1 fix in
  `arm-smmu.c`). Harness `~/vibe-coding-projects/coding/lg-v30-port` (branch
  master, clean). Downstream ref `~/.../android_kernel_lge_msm8998`. edk2
  `~/.../edk2-msm8998` (shallow, source-read only).
- **Test runner:** `scripts/tethered-test.sh <boot.img> [timeout]` — one-client
  fastboot discipline, LOS-return classification, PON/bootreason readback, and
  explicit exit codes for "device absent / unfamiliar USB state / still
  fastboot". Read its header. Build images: `cat Image.gz <dtb> > k; mkbootimg
  --kernel k --ramdisk out/initramfs-k023b.cpio.gz --base 0 --pagesize 4096
  --cmdline "androidboot.hardware=joan panic=0 ignore_loglevel" --output X`.
- **Full history:** `docs/kernel-change-ledger.md` (K001–K041, every test).
  Consolidated handoff: `docs/handoff-2026-07-08-mm-noc-current.md`.
  Attribution/borrowed-code table: `docs/public-upstreaming-plan.md`
  (Attribution section) — the msm8998 interconnect provider, if ever written,
  derives from `sdm660.c` (AngeloGioacchino Del Regno / SoMainline) + `msm8996.c`
  (Yassine Oudjana); keep their copyright + mark "based on".
- **Safety (binding):** RAM-only `fastboot boot`, never flash. `adb reboot
  bootloader` to enter fastboot (menu-entry wedges aboot). Exactly one fastboot
  client. Never `fastboot getvar` (wedges aboot). `sudo -n fastboot`. `panic=0`
  on classifier tests. Lance physically present for device work. Watch charge
  across many consecutive tethered boots (a weak USB port caused a pause). If
  the phone shows an unfamiliar USB id and hangs, it's usually recoverable with
  a Volume-Down-hold restart — look at the screen before assuming.
- **Commit trailers:** `Signed-off-by: Lance <Gero3977@gmail.com>` +
  `Assisted-by: Claude-Code:<model actually running>`; never `Co-Authored-By`.

## Recommended next move

If you have a UART cable or can boot the edk2 UEFI: do that first — it turns
the aggressive-init hunt from blind coin-flips into a clean read. Otherwise,
start the blind `initcall_blacklist` bisection of the driver probes the UEFI
doesn't run (gcc clock, arm-smmu non-reset path, early scm/rpmh), one per boot.
