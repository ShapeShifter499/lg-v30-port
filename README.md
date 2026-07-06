# LG V30 (joan, US998) mainline Linux port

Multi-agent project home. Any agent (or human) picking up a work parcel starts
here — this file is the single source of truth for state and conventions.
Coordination happens on **Deck board 4 "Shared Tasks", epic card #43** plus one
card per parcel. Artifacts that Lance should see go to
`Talk/Shared_AI_agents_files/{handoffs,patches,status}/` with a pointer in the
card.

## Goal

Boot modern mainline Linux (6.x) on Lance's LG V30 **US998**. First userspace
target: postmarketOS. Stretch: AOSP-on-mainline. The phone's daily driver will
be LineageOS 22.2 (Android 15 on downstream 4.4) — the port never touches that
install: test kernels boot tethered (`fastboot boot`) or from the recovery
partition.

Full background: `docs/recon-2026-07-04.md` (also on NC:
`Shared_AI_agents_files/status/2026-07-04_lg-v30-joan-mainline-recon.md`).

## Repos and paths (all on nym-nest)

| What | Where |
|---|---|
| This project (harness, docs) | `~/vibe-coding-projects/coding/lg-v30-port/` |
| Mainline kernel work tree | `~/vibe-coding-projects/coding/linux-mainline-v30/`, active clean tethered-test branch **`joan/latest-clean-test`**; debug branch `joan/latest-kernel` and older refs `lge-joan-bringup` / `joan/bringup-debug` are preserved |
| Board DTS | `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts` (first commit `3d3868854`, see its body for design decisions) |
| Downstream reference kernel | `~/vibe-coding-projects/coding/android_kernel_lge_msm8998/` (LineageOS 4.4, **read-only reference — never build or modify**) |
| Downstream joan DTS | `arch/arm64/boot/dts/lge/msm8998-joan/` in the downstream tree |

## Build + test image

```bash
cd ~/vibe-coding-projects/coding/linux-mainline-v30
# config = arm64 defconfig + these forced built-in (gadget/pstore from initramfs):
#   scripts/config --enable USB_CONFIGFS --enable PHY_QCOM_QUSB2 \
#     --enable PSTORE_RAM --enable PSTORE_CONSOLE --enable PSTORE_PMSG && make ... olddefconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 Image.gz dtbs

cd ~/vibe-coding-projects/coding/lg-v30-port
./make-testimage.sh          # → out/boot-joan-mainline.img
```

The initramfs (`initramfs/root/init`) brings up a USB ECM+ACM gadget at
172.16.42.1 with telnetd and a ttyGS0 shell. Milestone 1 = phone enumerates on
the host (`lsusb`), then `ip addr add 172.16.42.2/24 dev <usb-if>` and
`telnet 172.16.42.1`.

Boot format (from LineageOS BoardConfig): `Image.gz-dtb` appended DTB, base
0x0, pagesize 4096. LG aboot may not support `fastboot boot` — untested;
fallback is flashing the **recovery** partition (never boot) and key-combo
booting it (Vol-Down + Power, release/re-hold Power at the LG logo).

## Work parcels

Each parcel has a Deck card. **Claim = assign yourself / comment on the card
and move it to Active.** Don't work an unclaimed-by-you card that's already
Active. Parcels marked *no-device* are fully doable without the phone.

| # | Parcel | Card | Needs device? | Depends on |
|---|---|---|---|---|
| P0 | Verify kernel build + boot.img packaging | #43 (epic) | no | — (Ember, in progress) |
| P1 | Cross-check RPM regulator voltages vs downstream `msm8998-joan-common-pm.dtsi`; fix `msm8998-lge-joan.dts` (currently copied from OnePlus 5) | see board | no | — |
| P2 | Extract SW43402 panel data from downstream (`dsi-panel-sw43402*.dtsi`): DSI init sequence, timings, DSC PPS params → `docs/panel-sw43402.md` | see board | no | — |
| P3 | DSC-on-MDP5 feasibility verdict: read mainline `drivers/gpu/drm/msm` (mdp5 vs dpu DSC), downstream DSC usage; deliverable = written verdict + recommended display path in `docs/display-path.md` | see board | no | — |
| P4 | Draft touchscreen node: downstream `msm8998-joan-touch-stm-ftm4.dtsi` → mainline `stmfts` DT node (i2c bus, gpios, supplies), committed `status = "disabled"` | see board | no | P1 helps |
| P5 | Device chunk: confirm stock Pie, `fastboot oem unlock`, LineageOS 22.2 install, test `fastboot boot`, read actual hw rev + board-id, first tethered mainline boot | see board | **yes + Lance** | P0 |
| P6 | pmOS `device-lg-joan` package skeleton (pmaports layout, deviceinfo, kernel APKBUILD against our branch) | later | no | P5 proof of life |

## Conventions (binding)

- **Commits**: kernel-style subjects (`arm64: dts: qcom: ...`), detailed body
  (what + why), author `Lance <Gero3977@gmail.com>`, trailers per kernel.org
  coding-assistant policy:
  `Signed-off-by: Lance <Gero3977@gmail.com>` +
  `Assisted-by: <your-harness>:<model actually running>` (e.g.
  `Claude-Code:claude-fable-5`, `OpenClaw:<model>`). Never `Co-Authored-By`.
  See `~/vibe-coding-projects/README.md` for the full policy.
- **Branches**: small topic branches `joan/<topic>` off `lge-joan-bringup`,
  merged back into `lge-joan-bringup` when the parcel is done. Don't rebase or
  amend another agent's commits.
- **Attribution on docs/artifacts**: append `Written-by:` / `Agent-harness:` /
  `Date:` lines with *your* identity and the model running at write time.
  Never replace an earlier agent's attribution — append beneath it.
- **Safety**: nothing in this project flashes, deletes, or modifies the phone
  or any partition without Lance present and approving. Test images are built
  to `lg-v30-port/out/` and go nowhere else. The downstream kernel tree is
  reference-only.
- **State**: when you finish or hand off, update your parcel card and, if the
  facts here changed, this README (append, don't rewrite history).
- **Kernel change tracking**: every kernel-impacting change must also be entered
  in `docs/kernel-change-ledger.md` before handoff, whether it is a final
  upstreamable commit, bringup-only patch, debug oracle, or rejected experiment.
  Entries need the commit hash or saved patch path, touched files, evidence, and
  status (`upstream-candidate`, `bringup-local`, `debug-only`, `rejected`, or
  `unknown`). Public/PR-ready work must also satisfy
  `docs/public-upstreaming-plan.md`: clean topic commits, detailed rationale,
  verification evidence, no debug-only leftovers, and required trailers.

## Current status (2026-07-06)

- **P5/debug continued — latest upstream still reboots before debug output.**
  Aurel rebased the joan debug stack onto fetched upstream `origin/master`
  `8cdeaa50e` (`Linux 7.2-rc2`) as branch `joan/latest-kernel`, then made a
  cleaner tethered-test branch `joan/latest-clean-test` with only the four DTS
  commits (no `head.S`/`setup_arch` breadcrumb instrumentation). Clean build
  succeeded and produced RAM-only image `out/boot-joan-latest-clean.img` (sha256
  `47418aebd86c929b59cd09d243d93abe7ab03d85310d11015dfcd530474d47c1`). A
  one-client `fastboot boot` succeeded, but the phone returned to LineageOS at
  `t+46.7s` after boot handoff with no mainline mass-storage/debug channel.
  Latest upstream plus clean joan DTS work still does **not** fix the reset.
  The earlier debug branch image `out/boot-joan-latest-kernel.img` returned at
  `t+29.7s`; prefer the clean branch for future baseline testing because the
  breadcrumb commit is known debug-only and may perturb timing.
- **Reset source remains unresolved, but narrowed.** Aurel tested the obvious
  downstream `SEC_WDOG_DIS` translations plus discriminators. `panic=30` and
  disabling the APSS watchdog DT node did **not** shift the reset window; a PSCI
  timing oracle at `qcom_scm_probe()` proved SCM probe is reached early enough.
  A downstream LineageOS runtime check showed the downstream `SEC_WDOG_DIS`
  sysfs path itself fails with `0x42000107 ret=-2`, so it is not a known-good
  survival path. Clean APSS WDT takeover tests matching downstream bark/bite/pet
  behavior, including EN=3 for `qcom,wakeup-enable`, still rebooted to LineageOS
  before mainline USB/diag appears.
- **Latest new-path tests also failed.** Aurel tested single-core boot
  (`maxcpus=1`, image sha256
  `5bd01b0a987563027abbb968810b1b796201cbffb32e99effa4fc95d672c93e8`,
  LineageOS return `t+29.5s`), CPU idle disabled (`cpuidle.off=1 nohlt`, sha256
  `3f4b26656dc1af381128aa211787297ce85808e638287a1c21f7c550b5f9955d`,
  return `t+45.8s`), and a debug-only downstream high-memory reservation patch
  (`out/aurel-latest-highmem-reserve-test-2026-07-06.patch`, image sha256
  `c9f4545b790084dd82b139109dc29dffa516f1c3a17620a003db3b6241a886a6`,
  return `t+29.4s`). None exposed mainline USB/diag. Full table and
  next-analysis notes are in `docs/bringup-debug-state-2026-07-06.md`.
- **Secure-liveness diff follow-up: DLOAD-off argument shape is not the fix.**
  Downstream `msm-poweroff.c` on LGE builds defaults `download_mode=0` and its
  `pure_initcall` issues `set_dload_mode(0)`, which sends SCM boot command
  `SCM_DLOAD_CMD` (`0x10`) with args `(0, 0)`. Mainline `qcom_scm` used the same
  command but represented the off request as args `(0x10, 0)`. Aurel tested a
  debug-only patch changing mainline's off request to downstream's `(0, 0)`
  shape (`out/aurel-latest-dload-off-argshape-test-2026-07-06.patch`; image
  `out/boot-joan-latest-dload-off-argshape.img`, sha256
  `423d0c7f306a0d1617ade6577c8cb012df71cda6d6f8a08ab731dc4e79a26457`).
  `fastboot boot` succeeded but no mainline USB/diag appeared; LineageOS adb
  returned at `t+44.3s` and the post-reset PON log again showed SID0
  `PS_HOLD`. The patch was saved, reverted, and the kernel was rebuilt clean.
- **QSEE/QSEEOS log-buffer ping also failed as a survival oracle.** Aurel then
  matched downstream `tz_log.c`'s ARMv8 `SCM_QSEEOS_FNID(1, 6)` QSEE log-buffer
  registration as a debug-only qcom_scm probe call using a 32 KiB TZ memory
  buffer (`out/aurel-latest-qsee-logbuf-oracle-2026-07-06.patch`; image
  `out/boot-joan-latest-qsee-logbuf.img`, sha256
  `6a99c6f2c653e21d2cbba2df7ad2d392dbbcc40f0db7fef63efd599d57b7eb93`).
  RAM-only `fastboot boot` succeeded, but no mainline USB/diag appeared;
  LineageOS adb returned at `t+52.2s`, and PON evidence still showed SID0
  `PS_HOLD`. The patch was saved, reverted, and the kernel rebuilt clean.

## Previous status (2026-07-05)

- **P0 DONE — test image ready for tethered boot.** Kernel built clean
  (`Image.gz` 14.7 MB, joan DTB rebuilt) and packaged:
  `out/boot-joan-mainline.img` (15.5 MB,
  sha256 `c900dd1583fc7d760361e615dd69810165f4306171264c90fb617d1c378b0df9`).
  Image verified by unpack: bootimg header v0, base 0x0, pagesize 4096,
  kernel @0x8000 / ramdisk @0x1000000 / tags @0x100, kernel section =
  byte-exact `Image.gz` + appended DTB, ramdisk carries `init` +
  static aarch64 busybox. First device test (P5, needs Lance):
  `fastboot boot out/boot-joan-mainline.img`, then watch `lsusb` for
  18d1:4e26 "V30 mainline bring-up".

## Previous status (2026-07-04)

- Recon done (see docs/). Kernel scaffold committed (`3d3868854`); DTB
  compiles. `Image.gz` rebuild with gadget configs built-in was backgrounded on
  nym-nest — if `arch/arm64/boot/Image.gz` is missing, rerun the build line
  above. Test-image pipeline untested until the kernel image exists (P0).
- Phone not yet confirmed/connected; P5 blocked on Lance.
- Toolchain installed on nym-nest: `aarch64-linux-gnu-gcc` 16.1,
  `android-tools` (adb/fastboot/mkbootimg), `dtc`. `dtschema` NOT installed, so
  `CHECK_DTBS=y` doesn't work yet — install it if you want binding checks.

---
Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-04

Updated-by: Ember Nymbrand (agent-ember) — P0 completion status
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-05
