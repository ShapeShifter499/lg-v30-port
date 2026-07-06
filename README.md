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
- **RPM `rpm_requests` reachability oracle did not produce survival.** Downstream
  brings APSS-RPM communication over GLINK up early (`msm_rpm_dev_probe`,
  `rpm_requests` around `0.332s` in downstream dmesg). Mainline already has
  `qcom,glink-rpm` / `qcom,glink-smd-rpm` nodes and built-in RPM/SMEM/SMP2P
  support, so Aurel tested a debug-only timing oracle in
  `drivers/soc/qcom/smd-rpm.c`: if the `rpm_requests` rpmsg driver probes on
  `lge,joan`, wait 4 seconds then issue PSCI `SYSTEM_RESET`.
  (`out/aurel-latest-rpm-rpmsg-reachability-oracle-2026-07-06.patch`; image
  `out/boot-joan-latest-rpm-rpmsg-oracle.img`, sha256
  `d7b039b381ad83c61a4e7bfdf3005fa143a8fc5701c90dbf9faf06edfe1bed6b`).
  RAM-only `fastboot boot` succeeded, but no mainline USB/diag appeared;
  LineageOS adb returned at `t+58.3s`, and PON evidence again showed SID0
  `PS_HOLD`. The delayed timing suggests mainline likely reaches the RPM
  `rpm_requests` rpmsg probe before reset, but the reachability/liveness ping is
  not survival. The patch was saved, reverted, and the kernel rebuilt clean.
- **RPM BOB-mode state-changing oracle also did not expose diagnostics.**
  Downstream joan enables the PMI8998/PM8998 BOB RPM regulator path and sets
  `qcom,init-bob-mode = <2>` (`AUTO`) for `pmi8998_bob` and pin-control child
  regulators; mainline joan currently has no `rpm-pmi8998-regulators` / BOB
  regulator child nodes. Aurel tested a minimal debug-only RPM write in
  `drivers/soc/qcom/smd-rpm.c` after `rpm_requests` probe: send KVP `bobm=2` to
  resource `BOBB:1` in active and sleep sets
  (`out/aurel-latest-rpm-bob-mode-oracle-2026-07-06.patch`; image
  `out/boot-joan-latest-rpm-bob-mode.img`, sha256
  `e7ccb54378f39b84a3497590844d26d504e5cc770040190bab86e5e845f7c1c9`).
  RAM-only `fastboot boot` succeeded, but no mainline USB/diag appeared; the
  monitor timed out at `t+108.4s` with no adb/no mainline channel, then a
  follow-up host check found LineageOS adb and PON evidence again showed SID0
  `PS_HOLD`. This bare BOB-mode vote is not sufficient, but the longer failure
  timing keeps full downstream RPM regulator/default-vote parity worth comparing.
  The patch was saved, reverted, and the kernel rebuilt clean.
- **DT-backed RPM L19 default-vote oracle also still ended in controlled PS_HOLD.**
  Downstream joan's sound overlay forces `pm8998_l19` to 3.3 V with
  `qcom,init-voltage`, `qcom,vdd-voltage-level`, and `regulator-always-on`;
  mainline joan inherited the generic MSM8998 `l19` setting of 3.008 V with no
  boot/always-on flags. Aurel tested a minimal DT-only oracle in
  `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts` that changed `vreg_l19a_3p0`
  to 3.3 V and marked it `regulator-boot-on`/`regulator-always-on`
  (`out/aurel-latest-rpm-l19-always-on-oracle-2026-07-06.patch`; image
  `out/boot-joan-latest-rpm-l19-always-on.img`, sha256
  `84134c0d71c7f7eafae9e6a268c50302238a002b6c11c229baa6b52a6ee96e04`).
  RAM-only `fastboot boot` succeeded, but no mainline USB/diag appeared;
  LineageOS adb returned at `t+57.8s`, and PON evidence again showed SID0
  `PS_HOLD`. This minimal DT-backed default vote is not sufficient by itself,
  though it keeps broader downstream PM/RPM regulator parity worth testing.
  The patch was saved, reverted, and the kernel rebuilt clean.
- **Broader DT-backed PM/RPM overlay oracle also failed.**
  Aurel tested a one-bundle downstream PM overlay parity oracle through the
  existing mainline RPM regulator framework: `l18` fixed at 2.704 V and
  `regulator-boot-on`, `l19` fixed at 3.3 V with boot/always-on, and `bob` fixed
  at 3.312 V with boot/always-on (`out/aurel-latest-rpm-pm-overlay-oracle-2026-07-06.patch`; image `out/boot-joan-latest-rpm-pm-overlay.img`, sha256
  `de729e6eff09e997de15bdfb0fcf29890e86765228d691f5bb1ca1e185806365`). RAM-only `fastboot boot` succeeded, but no mainline USB/diag
  appeared; LineageOS adb returned at `t+30.6s` after fastboot and PON evidence
  again showed SID0 `PS_HOLD`. This broader DT-backed PM/RPM default-vote bundle
  is not sufficient and does not preserve the longer timing seen with the raw
  BOB-mode oracle. The patch was saved, reverted, and the kernel rebuilt clean.

- **TCSR DLOAD/restart-cookie oracle also failed.**
  Aurel compared downstream's MSM8998 restart/IMEM setup and found that
  downstream exposes `qcom,msm-imem@146bf000` plus a `qcom,pshold` fallback
  `tcsr-boot-misc-detect` resource at `0x1fd3000` (`tcsr_regs_2 + 0x13000`),
  while mainline MSM8998 had no equivalent DLOAD cookie phandle. The oracle added
  `qcom,dload-mode = <&tcsr_regs_2 0x13000>` to mainline SCM so
  `qcom_scm_set_download_mode(0)` clears the same TCSR boot-misc DLOAD bits
  (`out/aurel-latest-tcsr-dload-cookie-oracle-2026-07-06.patch`; image `out/boot-joan-latest-tcsr-dload-cookie.img`, sha256 `0ba46735f6f6fac182f3de3f67fe46f5c60c26948be7b1193f7c7147b48645dd`). RAM-only `fastboot boot`
  succeeded, but no mainline USB/diag appeared; LineageOS adb returned at
  `t+55.5s` from test start, and PON evidence again showed SID0 `PS_HOLD`. This
  TCSR DLOAD/restart-cookie route is not sufficient as a standalone liveness
  fix. The patch was saved, reverted, and the kernel rebuilt clean.


- **PM8998 PON S3 source/debounce oracle also failed.**
  Aurel compared downstream joan PMIC/PON setup and found an unsupported
  downstream delta: PM8998 PON programs `qcom,s3-debounce = <32>` and
  `qcom,s3-src = "kpdpwr-and-resin"`, while upstream `qcom-pon` only handles
  reboot-mode spare bits and child population. The DEBUG-ONLY oracle added a
  minimal `qcom-pon` S3 source/debounce programming path plus a joan
  `&pm8998_pon` override, and verified `CONFIG_POWER_RESET_QCOM_PON=y`
  (`out/aurel-latest-pon-s3-oracle-2026-07-06.patch`, sha256 `e8dfba3949f4ace1d678ed94ce7e254287197ba4c6ee0d6368d4efa642dc051d`; config `out/aurel-latest-pon-s3-oracle-config-2026-07-06.txt`, sha256 `bababe3d52ff1bd1e7b6ede056c8986696260024010f38ab56696039b0bb193c`;
  image `out/boot-joan-latest-pon-s3-oracle.img`, sha256 `2c83d4782aa60564c840efe5122ebfeb9aa30f8e0aea8bab10fc7d70f6fb2c31`). RAM-only `fastboot boot` succeeded
  (`Sending`/`Booting` OKAY, total `5.510s`), but no mainline USB/diag appeared;
  LineageOS adb returned at `t+30.5s`, and post-reset PON evidence again showed
  SID0 `PS_HOLD`. The downstream PON S3 source/debounce delta is not sufficient
  as a standalone liveness fix. The patch was saved, reverted, and the kernel
  rebuilt clean (`out/boot-joan-latest-clean-post-pon-s3-oracle.img`, sha256 `7d87765d96df926cac538563dcbe1989f8990d9b784b1c0163926f5cb5f0b0ef`).


- **PM8998 PON reset-sequence/S1/S2 oracle also failed.**
  Aurel then tested the next fuller downstream PON delta: in addition to the S3
  source/debounce values, downstream joan disables S2 reset on `pon_1`/`pon_2`
  and enables `pon_3` (`KPDPWR_N AND RESIN_N`) with `qcom,s1-timer = <6720>`,
  `qcom,s2-timer = <2000>`, and `qcom,s2-type = <0x08>`
  (`PON_POWER_OFF_DVDD_HARD_RESET`). The DEBUG-ONLY oracle added a minimal
  upstream `qcom-pon` reset-sequence programming path and joan DT child nodes
  (`out/aurel-latest-pon-reset-seq-oracle-2026-07-06.patch`, sha256 `588264cfb140c0c307a57b8898f5c1c77bf8fa623da32e68ffaa7ce66f9f552c`; config `out/aurel-latest-pon-reset-seq-oracle-config-2026-07-06.txt`, sha256 `bababe3d52ff1bd1e7b6ede056c8986696260024010f38ab56696039b0bb193c`;
  image `out/boot-joan-latest-pon-reset-seq-oracle.img`, sha256 `a0c0e2b6448981798d5cc5b03a4804504caaedff7705a896a42883d86786ee12`). RAM-only `fastboot boot` succeeded
  (`Sending`/`Booting` OKAY, total `5.522s`), but no mainline USB/diag appeared;
  LineageOS adb returned at `t+57.6s` host-script time (`~46.3s` after the
  fastboot command returned), and post-reset PON evidence again showed SID0
  `PS_HOLD`. The fuller downstream PM8998 PON reset-sequence delta is not
  sufficient as a standalone liveness fix. The patch was saved, reverted, and
  the kernel rebuilt clean (`out/boot-joan-latest-clean-post-pon-reset-seq-oracle.img`, sha256 `d543f234ab848f2de12191eca3cf2df2aa87b04711e4665564da93f5cf57f418`).


- **CPU/Kryo SCM errata comparison produced no boot oracle.**
  Aurel compared downstream `drivers/soc/qcom/scm-errata.c` against mainline.
  Downstream has an optional debugfs/hotcpu helper for Kryo errata command `0x12`
  (`E74/E75` enable arg `0x1`, `E76` disable arg `0x100`), but joan defconfigs
  do not enable `CONFIG_QCOM_SCM_ERRATA`, and the helper does not apply itself
  to already-online boot CPUs at init. This is not active downstream default boot
  parity, so no RAM-boot oracle was built. Status artifact:
  `out/aurel-kryo-scm-comparison-2026-07-06.txt`.

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

Updated-by: Aurel Nymvale (agent-aurel) — PM8998 PON S3 oracle result
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

Updated-by: Aurel Nymvale (agent-aurel) — Kryo SCM errata comparison
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06
