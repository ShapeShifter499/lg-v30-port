# LG V30 (joan, US998) mainline Linux port

Project home for humans and AI agents alike. Anyone picking up a work parcel
starts here. **Contributions are welcome via GitHub pull requests and issues**
on the project repos — see [CONTRIBUTING.md](CONTRIBUTING.md):

- this repo — harness, docs, evidence;
- [`linux-lg-v30-joan`](https://github.com/ShapeShifter499/linux-lg-v30-joan)
  — the kernel (see [branches](#branches) below);
- [`pmaports-lge-joan`](https://github.com/ShapeShifter499/pmaports-lge-joan)
  — the postmarketOS device port, kept as a pmaports fork so it can become
  the upstream pmaports merge request. The active branch is
  `joan/readme-build-guide` plus feature branches (see
  [Branches](#branches)); the default branch `device-lge-joan` is stale.
  The packages inside are named `lg-joan` (`linux-lg-joan`, `device-lg-joan`,
  `firmware-lg-joan`) since 2026-10-03; the repo name was not changed;
- [`lg-v30-joan-pmos-packages`](https://github.com/ShapeShifter499/lg-v30-joan-pmos-packages)
  — a mirror of the joan packages (a subset of pmaports `device/testing` and
  `temp`; it can drift: `gtk4.0` differs, see below).

Historical docs under `docs/` also mention an internal tracker (Deck
"cards") and an "internal mirror" used by the original maintainers' agents;
those are not publicly accessible and nothing essential lives only there.

## Goal

Boot modern mainline Linux on Lance's LG V30 **US998**. First userspace
target: postmarketOS. Stretch: AOSP-on-mainline. The phone's daily driver is
LineageOS 22.2 (Android 15 on downstream 4.4) — the port never touches that
install: test kernels boot tethered (`fastboot boot`, RAM-only) or from the
recovery partition.

## Current state (2026-10-27)

**The source of truth for per-block status is
[`docs/joan-hardware-support-matrix.md`](docs/joan-hardware-support-matrix.md)**
(last full pass 2026-09-26, rows updated individually through 2026-10-10).
This section is only a dated pointer; where it and the matrix disagree, the
matrix wins. Nothing below was re-tested on a phone on 2026-10-27: it is read
from the repo histories. Anything marked *unverified* has no on-device
evidence in these repos.

- **Kernel:** mainline **v7.3-rc6** merged into the joan line (2026-10-09).
  Board DTS `arch/arm64/boot/dts/qcom/msm8998-lg-joan.dts` (renamed from
  `lge` on 2026-10-03). `master` and `joan/latest-clean-test` were both at
  `dc9c6692dbfb` (2026-10-25). Some old commit hashes in these docs predate a
  history rewrite: [`docs/kernel-history-rewrite.md`](docs/kernel-history-rewrite.md).
- **postmarketOS:** pmaports `linux-lg-joan` 7.3.0_rc6 r6 and `device-lg-joan`
  r29 on branch `joan/readme-build-guide` (2026-10-11); packages are named
  `lg-joan` since 2026-10-03.
- **Boots to Phosh** from microSD with 0 failed units on the matrix's
  2026-10-06/07 and 2026-10-09 passes (fresh `pmbootstrap install --no-split
  --sector-size 512`). Display, touch, GPU (freedreno, DVFS), Bluetooth,
  Wi-Fi, NFC, USB gadget/host, wired charging, CAMSS with the IMX351 main
  camera, and cellular data are marked working or partial in the matrix.
- **Wi-Fi works** (WCN3990, ath10k_snoc). `wlanmdsp.mbn` ships in
  `firmware-lg-joan` for the h930 and h932 trees. The packaged tree for
  `us998` holds only an `ath10k` `board.bin` that no package installs;
  whether the US998 phone relies on the h93x blobs is *unverified* here.
  Per-model board data is an open matrix item.

Open issues (details and evidence in the matrix):

- **Cellular boot-time RX stall** (IPA/GSI): on 10 of 16 r60 boots on
  2026-10-07, and again on 2026-10-09; not root-caused. Wi-Fi does not return
  after a modem restart.
- **Unbooted or untested:** USB-C DisplayPort alt mode (no DP sink tried),
  CPU speed bins 0 and 1 (need a phone with those fuses), the sensor DSP's
  sensors (SLPI boots; no registry server), FM audio path (the slim2 NGD
  hard-hangs the SoC), the Samsung and Hynix camera colour/exposure,
  physical NFC tags, wireless charging, GNSS.
- **Known failures:** `callaudiod` crashed on r27 (call audio), fingerprint
  (TEE-only on stock), UFS about 4x slower than stock, SX9320 SAR proximity
  has no driver.
- **Packaging drift:** the pmaports default branch `device-lge-joan` is stale
  (2026-09-06); the active branch `joan/readme-build-guide` and the feature
  branches `smgr-iio-build`, `bu24235-power-package`, `audio-ucm-r12`,
  `ucm-cardid-fix`, `awb-stats-window` and `v7.3-rc6-candidate` are not
  merged into each other. `readme-build-guide` pins the kernel at `5ad31136`
  while `smgr-iio-build` pins `dc9c6692` (current kernel head). The
  `lg-v30-joan-pmos-packages` mirror's `gtk4.0` (r3, 3 patches) differs from
  `readme-build-guide`'s (r1, 2 patches).
- **Code that still uses the old name:** `scripts/lib/bootimg.sh` looks for
  `msm8998-lge-joan.dtb`; the kernel DTB is now `msm8998-lg-joan.dtb`.
  Untested here; pass the new path or fix the script before relying on it.

Next steps, in order:

1. Pick one pmaports line as the integration branch: merge or retire the
   feature branches, re-pin the kernel to current `master`, and refresh the
   default branch.
2. Root-cause the IPA/GSI boot-time RX stall (`docs/evidence/2026-10-09-ipa-rx-stall/`).
3. Bench the untested hardware that needs only a cable or a tag: a USB-C
   DP/HDMI adapter, physical NFC tags, a bin 0/1 phone if one exists.
4. Close the audio gaps: callaudiod, headset detection, FM audio route.
5. Sensors: an sns-reg registry server and the SMGR IIO series.
6. Keep the matrix, `docs/kernel-change-ledger.md` and the candidate closure
   packets current; this README only needs the dated summary above.

The 2026-08-10 state and the 2026-09-24 update that used to be here are in
[`docs/status-history.md`](docs/status-history.md). The latest handoff is
[`docs/handoff-2026-10-09-aurel-ipa-stall.md`](docs/handoff-2026-10-09-aurel-ipa-stall.md);
the 2026-10-03 overview of boot and open issues is
[`docs/handoff-2026-10-03-boot-and-open-issues.md`](docs/handoff-2026-10-03-boot-and-open-issues.md).

### Read first

1. This README.
2. [`docs/joan-hardware-support-matrix.md`](docs/joan-hardware-support-matrix.md)
   — per-block status; the source of truth for what works.
3. [`docs/README.md`](docs/README.md) — index of every doc, grouped by topic.
4. [`docs/test-results/README.md`](docs/test-results/README.md) — the
   mandatory candidate-test index (read before any device work).
5. [`docs/kernel-change-ledger.md`](docs/kernel-change-ledger.md) — every
   kernel-impacting change, with evidence.
6. [`docs/joan-firmware-and-package-requirements.md`](docs/joan-firmware-and-package-requirements.md)
   — what firmware to extract from your own phone, and the kernel config.

Older status snapshots (2026-07-04 .. 2026-09-24) live in
[`docs/status-history.md`](docs/status-history.md).

## Branches

Kernel ([`linux-lg-v30-joan`](https://github.com/ShapeShifter499/linux-lg-v30-joan)),
as set by Lance on 2026-08-10
([details](docs/ember-handoff-2026-08-10-branch-convention-corrected.md)):

- **`master`** — verified fixes only, clean history.
- **`joan/latest-clean-test`** — the raw "booting but ugly" working history:
  experiments, diagnostics and their reverts are kept on purpose as the record
  of what was tried and what stuck. Same content as `master`, more history.
  (Both were at `dc9c6692dbfb` on 2026-10-25; the kernel base is mainline
  v7.3-rc6. The pmaports `linux-lg-joan` package pins a commit on this line.)

Topic work happens on `joan/<topic>` branches and arrives by pull request.
Don't rebase or amend another contributor's commits. (Older docs describe
`lge-joan-bringup` as the integration branch; that is historical. Some
commit hashes in older docs predate a history rewrite; see
[`docs/kernel-history-rewrite.md`](docs/kernel-history-rewrite.md).)

postmarketOS ([`pmaports-lge-joan`](https://github.com/ShapeShifter499/pmaports-lge-joan)),
state on 2026-10-27:

- **`joan/readme-build-guide`** — the active branch: `linux-lg-joan`
  7.3.0_rc6-r6 and `device-lg-joan` r29, with the build guide.
  Kernel config: `device/testing/linux-lg-joan/config-lg-joan.aarch64`.
- Feature branches (not merged into it): `joan/smgr-iio-build`,
  `joan/bu24235-power-package`, `joan/audio-ucm-r12`, `joan/ucm-cardid-fix`,
  `joan/awb-stats-window`, `joan/v7.3-rc6-candidate`.
- **`device-lge-joan`** — the GitHub default branch; last commit 2026-09-06,
  stale. (The packages were renamed `lge` → `lg` on 2026-10-03; the branch and
  repo names were not.)

## Repo layout

| Path | What |
|---|---|
| `make-testimage.sh` | bring-up image: kernel + [USB-gadget initramfs](initramfs/root/init) |
| `make-pmos-image.sh` | pmOS image: new kernel + ramdisk/cmdline reused from a working pmOS image |
| `make-pmos-image-fw.sh` | as above, plus GPU/BT firmware injected into the initramfs (legacy path) |
| `scripts/lib/bootimg.sh` | shared helpers: kernel lookup, joan `mkbootimg` offsets, (un)packing (still looks for `msm8998-lge-joan.dtb`; the DTB is now `msm8998-lg-joan.dtb`) |
| `scripts/tethered-test.sh` | safe tethered RAM-boot + classify runner (read its safety header) |
| `scripts/make-pmos-image-recovery.sh`, `scripts/patch-initramfs-recovery.sh` | pmOS initramfs with bounded, self-healing boot waits |
| `scripts/sd-fsck-repair.sh`, `scripts/sd-throughput.sh` | SD rootfs fsck (from LineageOS) and read-only SD benchmark |
| `scripts/read-pstore-partition.sh`, `scripts/read-imem-reset-reason.sh` | post-crash evidence readers (run from LineageOS) |
| `scripts/dtb-check-reg-overlaps.sh` | static MMIO-overlap check; run on every DTB before booting |
| `scripts/check.sh` | host-only repo health check (script syntax, shellcheck, doc links) |
| `scripts/install-git-hooks.sh`, `scripts/hooks/commit-msg` | attribution-trailer hook |
| `tools/` | static aarch64 probes (`msmprobe`, `msmsubmit`) and `wdkill`; `make -C tools`. Since 2026-10: `tools/bench`, `tools/memmap`, `tools/socmap` and helper scripts for the matrix work |
| `device/` | files installed on the pmOS rootfs (BT address service) |
| `docs/` | handoffs, test packets, ledger, downstream references — see [docs/README.md](docs/README.md); the status table is [`docs/joan-hardware-support-matrix.md`](docs/joan-hardware-support-matrix.md); bench evidence is in `docs/evidence/` |

## Build + test image

Host tools: `aarch64-linux-gnu-gcc`, `mkbootimg`/`unpack_bootimg` (AOSP
`system/tools/mkbootimg`), `cpio`, `gzip`, `python3`; `adb`/`fastboot` for
device work; optional `ccache`, `shellcheck`, `fdtget`.

```bash
# kernel: always build out-of-tree (O=). An in-tree build leaves the source
# tree "not clean" and breaks every later O= build.
cd <linux-lg-v30-joan checkout>
# current: the config the pmaports kernel package ships (not re-verified here as an O= build start)
cp <pmaports-lge-joan>/device/testing/linux-lg-joan/config-lg-joan.aarch64 "$O/.config"
# 2026-08 master only: cp <lg-v30-port>/docs/master-47041183b.config "$O/.config"
make O="$O" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     CC="ccache aarch64-linux-gnu-gcc" -j"$(nproc)" Image.gz modules dtbs

# images: KDIR is the kernel source tree or the O= build directory
cd <lg-v30-port>
scripts/dtb-check-reg-overlaps.sh "$O/arch/arm64/boot/dts/qcom/msm8998-lg-joan.dtb"
KDIR="$O" ./make-testimage.sh                                  # -> out/boot-joan-mainline.img
KDIR="$O" ./make-pmos-image.sh out/<working-pmos>.img out/<new>.img
```

Build traps that have cost real boots:

- **`make olddefconfig` does not enable newly available drivers.** Start from
  a known-good `.config` (`config-lg-joan.aarch64` in pmaports, or
  `docs/master-47041183b.config` for the August `master`) rather than
  `defconfig`/`olddefconfig`; that is how the fuel gauge went missing.
  RAM-booted kernels never match `/lib/modules`, so these must be `=y`, not
  `=m`: `BATTERY_PMI8998_FG CHARGER_QCOM_SMB2 QCOM_SPMI_RRADC
  QCOM_SPMI_ADC5 QCOM_SPMI_ADC_TM5 QCOM_Q6V5_MSS QRTR QRTR_SMD
  QCOM_SYSMON QCOM_RMTFS_MEM` (plus `TOUCHSCREEN_STMFTS` and
  `MSM_GPUCC_8998` — see the A182 and mas_ipa packets).
- **Compare image size with images already known to boot** before booting.
  A kernel ~1 MB light means a lost `.config`, not your code change
  ([write-up](docs/ember-2026-08-10-unpin-result-was-confounded.md)).
- ccache only applies with `CC="ccache aarch64-linux-gnu-gcc"`;
  `/usr/lib/ccache` shims native compilers only.

The bring-up initramfs (`initramfs/root/init`) brings up a USB ECM+ACM gadget at
172.16.42.1 with telnetd and a ttyGS0 shell: `ip addr add 172.16.42.2/24 dev
<usb-if>` then `telnet 172.16.42.1`.

Boot format (from LineageOS BoardConfig): `Image.gz-dtb` appended DTB, base
0x0, pagesize 4096, ramdisk offset 0x02000000 (see `scripts/lib/bootimg.sh`).
Test with `sudo -n fastboot boot <img>` after entering fastboot via
`adb reboot bootloader`. Recovery from a hang: hold Power + Volume-Down ~8 s,
which returns to LineageOS. After any early reset/panic, immediately run
`scripts/read-pstore-partition.sh` from LineageOS root. Fallback if
`fastboot boot` is ever unavailable: flash the **recovery** partition (never
boot) with Lance's approval, then key-combo boot it (Vol-Down + Power,
release/re-hold Power at the LG logo).

## Procedures

- **SD card filesystem (the pmOS rootfs lives on the microSD).** Runbook:
  `docs/sd-card-fsck-and-recovery.md`; helper: `scripts/sd-fsck-repair.sh`.
  - Read-only pre-boot check (no authorization needed):
    `IMG=<pmos-boot.img> scripts/sd-fsck-repair.sh check` — runs the pmOS
    initramfs's e2fsck 1.47.4 from LineageOS. LineageOS's own e2fsck 1.46.2
    cannot check `p2`; its "still has errors" means "could not check".
  - Repair (persistent write — Lance must be present and approving):
    `AUTH=yes-i-have-owner-authorization IMG=<img> scripts/sd-fsck-repair.sh repair`.
    Trigger: "FSCK repair wait timed out" on a RAM boot. rc 1 = corrected;
    rc >= 4 = hard errors, replace/reimage the card.
  - Set `HOST=<ssh-host>` if the phone is attached to another machine,
    `SERIAL=<adb-serial>` if more than one device is attached.
- **Before any push to this repo:** `scripts/check.sh`.

## Work parcels

**Claim a parcel by opening a GitHub issue on this repo (or commenting on an
existing one) so work isn't duplicated; deliver via pull request.**

| # | Parcel | Status | Needs device? |
|---|---|---|---|
| P0 | Kernel build + boot.img packaging | DONE | no |
| P1 | Cross-check RPM regulator voltages against downstream `msm8998-joan-common-pm.dtsi` | open | no |
| P2 | SW43402 panel data from downstream | DONE — `docs/panel-sw43402.md` | no |
| P3 | Display path verdict | DONE — DPU1, `docs/display-path.md` | no |
| P4 | FTS3670 touchscreen | DONE — device-proven; phantom contacts fixed 2026-08-10 | — |
| P5 | Unlock, LineageOS, first tethered mainline boot | DONE (2026-07-10) | — |
| P6 | pmOS device package | in progress in [`pmaports-lge-joan`](https://github.com/ShapeShifter499/pmaports-lge-joan) (branch `joan/readme-build-guide`) | no |
| P7 | Wi-Fi: WLFW service 69 / `wlanmdsp.mbn` | works per the matrix (`wlanmdsp.mbn` ships in `firmware-lg-joan` for h930/h932); open: per-model board data, Wi-Fi does not survive a modem restart | yes |
| P8 | A540 runtime PM: GPU never suspends (staged ICC-vote + unpin retest) | open | yes |
| P9 | Charging path moves current | open | yes |
| P10 | Suspend/resume (s2idle) | open | yes |
| P11 | Closure packets for the 2026-08-08..10 device work (see `docs/test-results/README.md`) | open | no |
| P12 | Power key IRQ stuck at 46: retest with the new debounce, or retire | open | yes |

## Conventions (binding)

- **Commits**: kernel-style subjects (`arm64: dts: qcom: ...`), detailed body
  (what + why), a DCO `Signed-off-by:` from the **human** contributor, and an
  `Assisted-by: <harness>:<provider>/<model actually running>` trailer for AI
  assistance (kernel.org coding-assistant policy). Never `Co-Authored-By` for
  AI, never an AI `Signed-off-by`. See [CONTRIBUTING.md](CONTRIBUTING.md);
  `scripts/install-git-hooks.sh` installs a hook that enforces this.
- **AI attribution on public docs/artifacts**: the same `Assisted-by:`
  identity, plus the date and update scope where useful.
- **Safety**: nothing in this project flashes, deletes, or modifies the phone
  or any partition without Lance present and approving. Test images are built
  to `out/` and go nowhere else. The downstream kernel tree is reference-only.
- **State**: when you finish or hand off, update your parcel issue and, if the
  facts here changed, the *Current state* section above. Move superseded
  snapshots to `docs/status-history.md` rather than deleting them.
- **Candidate closure packets**: after every device test or meaningful
  host-only candidate checkpoint, create `docs/test-results/<candidate>-<date>.md`
  from `docs/templates/candidate-test-closure.md` and update the read-first
  index. Except for immediate safety recovery, do not start the next
  experiment before closure. (Maintainers also mirror the result to their
  private tracker; outside contributors skip that step.)
- **Project history / attribution index**: when a session materially changes
  the project, update `docs/project-history-and-attribution.md`.
- **Dependency tracking**: any host package install or external source
  download made for this project gets a row in `docs/dependency-tracker.md`.
- **Kernel change tracking**: every kernel-impacting change is entered in
  `docs/kernel-change-ledger.md` before handoff, with commit hash or patch
  path, touched files, evidence, and status (`upstream-candidate`,
  `bringup-local`, `debug-only`, `rejected`, or `unknown`). Public/PR-ready
  work must also satisfy `docs/public-upstreaming-plan.md`.

## Provenance

See [PROVENANCE.md](PROVENANCE.md) for what is original to this project vs
borrowed/derived, and `docs/project-history-and-attribution.md` for who did
what, when.

## Original maintainers' local layout

For reading older docs only; any layout works if you set `KDIR`.

| What | Where |
|---|---|
| This project | `~/vibe-coding-projects/coding/lg-v30-port/` |
| Mainline kernel tree | `~/vibe-coding-projects/coding/linux-mainline-v30/` (the scripts' fallback when `KDIR` is unset) |
| 2026-08-10 build dir | `/data/buildcache/kbuild/build-integration-d38242fb5` |
| Downstream reference kernel | `~/vibe-coding-projects/coding/android_kernel_lge_msm8998/` (LineageOS 4.4, **read-only — never build or modify**); joan DTS under `arch/arm64/boot/dts/lge/msm8998-joan/` |
| Board DTS (kernel repo) | `arch/arm64/boot/dts/qcom/msm8998-lg-joan.dts` (was `msm8998-lge-joan.dts` before 2026-10-03) |

Assisted-by: Claude-Code
Date: 2026-09-23
Update-scope: README restructured around the 2026-08-10 state; history moved to docs/status-history.md.

Assisted-by: Grok Bot
Date: 2026-10-27
Update-scope: Current state, branches, build snippet and names refreshed from the repo histories (nothing re-tested on a phone); 2026-08-10 snapshot moved to docs/status-history.md.
