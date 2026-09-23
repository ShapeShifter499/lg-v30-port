# LG V30 (joan, US998) mainline Linux port

Project home for humans and AI agents alike. Anyone picking up a work parcel
starts here. **Contributions are welcome via GitHub pull requests and issues**
on the project repos — see [CONTRIBUTING.md](CONTRIBUTING.md):

- this repo — harness, docs, evidence;
- [`linux-lg-v30-joan`](https://github.com/ShapeShifter499/linux-lg-v30-joan)
  — the kernel (see [branches](#branches) below);
- [`pmaports-lge-joan`](https://github.com/ShapeShifter499/pmaports-lge-joan)
  (branch `device-lge-joan`) — the postmarketOS device port, kept as a
  pmaports fork so it can become the upstream pmaports merge request.

Historical docs under `docs/` also mention an internal tracker (Deck
"cards") and an "internal mirror" used by the original maintainers' agents;
those are not publicly accessible and nothing essential lives only there.

## Goal

Boot modern mainline Linux on Lance's LG V30 **US998**. First userspace
target: postmarketOS. Stretch: AOSP-on-mainline. The phone's daily driver is
LineageOS 22.2 (Android 15 on downstream 4.4) — the port never touches that
install: test kernels boot tethered (`fastboot boot`, RAM-only) or from the
recovery partition.

## Current state (2026-08-10)

Mainline (7.2-rc base) boots postmarketOS/Phosh from the microSD with:

| Area | State | Evidence |
|---|---|---|
| Display (SW43402, DSC, DPU1) + brightness 6–255 | works; rainbow-on-wake fixed (prepare() no longer forces DBV_MAX) | [rainbow write-up](docs/ember-2026-08-10-rainbow-on-wake-was-brightness.md) |
| GPU (Adreno 540, freedreno FD540) | renders, DVFS works; **never runtime-suspends** (deliberate PM pin) | [GPU-FULL3](docs/test-results/GPU-FULL3-2026-08-04.md), [unpin retest](docs/ember-2026-08-10-unpin-result-was-confounded.md) |
| Touch (FTS3670 / stmfts) | works; phantom-contact keypad freeze fixed | [touch fix](docs/ember-handoff-2026-08-10-touch-phantom-contacts.md) |
| Bluetooth (WCN3990) | works; stable derived BD address via `device/` service | [BT root cause](docs/ember-handoff-2026-08-09-bt-unconfigured-root-cause.md) |
| Interconnect / QoS | 17/17 masters programmed | [mas_ipa](docs/test-results/mas-ipa-2026-08-07.md) |
| Battery fuel gauge | works (`CONFIG_BATTERY_PMI8998_FG=y` required) | [FG test](docs/pmi8998-fg-rfc-test-report-2026-08-07.md) |
| Power key | vendor 31.25 ms debounce adopted | [session close](docs/ember-handoff-2026-08-10-session-close.md) |
| Wi-Fi | **blocked** on `wlanmdsp.mbn` (WLFW service 69) | [firmware reqs](docs/joan-firmware-and-package-requirements.md) |
| Modem | brought up; `rmtfs` still started by hand | [modem handoff](docs/ember-handoff-2026-08-08-modem-layer1-and-integration.md) |
| Charging path | open; needs the pack to drain to ~90 % to test | [session close](docs/ember-handoff-2026-08-10-session-close.md) |
| Suspend (s2idle) | open; a 2026-08-03 accidental s2idle rebooted | [A184](docs/test-results/A184-2026-08-03-host-only.md) |

Kernel `master` and `joan/latest-clean-test` were both `c861d1217` at the
2026-08-10 session close. The full hand-off, including the open lanes, is
[`docs/ember-handoff-2026-08-10-session-close.md`](docs/ember-handoff-2026-08-10-session-close.md).

### Read first

1. This README.
2. [`docs/README.md`](docs/README.md) — index of every doc, grouped by topic.
3. [`docs/test-results/README.md`](docs/test-results/README.md) — the
   mandatory candidate-test index (read before any device work).
4. [`docs/kernel-change-ledger.md`](docs/kernel-change-ledger.md) — every
   kernel-impacting change, with evidence.
5. [`docs/joan-firmware-and-package-requirements.md`](docs/joan-firmware-and-package-requirements.md)
   — what firmware to extract from your own phone, and the kernel config.

Older status snapshots (2026-07-04 .. 2026-08-03) live in
[`docs/status-history.md`](docs/status-history.md).

## Branches

Kernel ([`linux-lg-v30-joan`](https://github.com/ShapeShifter499/linux-lg-v30-joan)),
as set by Lance on 2026-08-10
([details](docs/ember-handoff-2026-08-10-branch-convention-corrected.md)):

- **`master`** — verified fixes only, clean history.
- **`joan/latest-clean-test`** — the raw "booting but ugly" working history:
  experiments, diagnostics and their reverts are kept on purpose as the record
  of what was tried and what stuck. Same content as `master`, more history.

Topic work happens on `joan/<topic>` branches and arrives by pull request.
Don't rebase or amend another contributor's commits. (Older docs describe
`lge-joan-bringup` as the integration branch; that is historical.)

## Repo layout

| Path | What |
|---|---|
| `make-testimage.sh` | bring-up image: kernel + [USB-gadget initramfs](initramfs/root/init) |
| `make-pmos-image.sh` | pmOS image: new kernel + ramdisk/cmdline reused from a working pmOS image |
| `make-pmos-image-fw.sh` | as above, plus GPU/BT firmware injected into the initramfs (legacy path) |
| `scripts/lib/bootimg.sh` | shared helpers: kernel lookup, joan `mkbootimg` offsets, (un)packing |
| `scripts/tethered-test.sh` | safe tethered RAM-boot + classify runner (read its safety header) |
| `scripts/make-pmos-image-recovery.sh`, `scripts/patch-initramfs-recovery.sh` | pmOS initramfs with bounded, self-healing boot waits |
| `scripts/sd-fsck-repair.sh`, `scripts/sd-throughput.sh` | SD rootfs fsck (from LineageOS) and read-only SD benchmark |
| `scripts/read-pstore-partition.sh`, `scripts/read-imem-reset-reason.sh` | post-crash evidence readers (run from LineageOS) |
| `scripts/dtb-check-reg-overlaps.sh` | static MMIO-overlap check; run on every DTB before booting |
| `scripts/check.sh` | host-only repo health check (script syntax, shellcheck, doc links) |
| `scripts/install-git-hooks.sh`, `scripts/hooks/commit-msg` | attribution-trailer hook |
| `tools/` | static aarch64 probes (`msmprobe`, `msmsubmit`) and `wdkill`; `make -C tools` |
| `device/` | files installed on the pmOS rootfs (BT address service) |
| `docs/` | handoffs, test packets, ledger, downstream references — see [docs/README.md](docs/README.md) |

## Build + test image

Host tools: `aarch64-linux-gnu-gcc`, `mkbootimg`/`unpack_bootimg` (AOSP
`system/tools/mkbootimg`), `cpio`, `gzip`, `python3`; `adb`/`fastboot` for
device work; optional `ccache`, `shellcheck`, `fdtget`.

```bash
# kernel: always build out-of-tree (O=). An in-tree build leaves the source
# tree "not clean" and breaks every later O= build.
cd <linux-lg-v30-joan checkout>
cp <lg-v30-port>/docs/master-47041183b.config "$O/.config"   # known-good config
make O="$O" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     CC="ccache aarch64-linux-gnu-gcc" -j"$(nproc)" Image.gz modules dtbs

# images: KDIR is the kernel source tree or the O= build directory
cd <lg-v30-port>
scripts/dtb-check-reg-overlaps.sh "$O/arch/arm64/boot/dts/qcom/msm8998-lge-joan.dtb"
KDIR="$O" ./make-testimage.sh                                  # -> out/boot-joan-mainline.img
KDIR="$O" ./make-pmos-image.sh out/<working-pmos>.img out/<new>.img
```

Build traps that have cost real boots:

- **`make olddefconfig` does not enable newly available drivers.** Start from
  a known-good `.config` (`docs/master-47041183b.config`) rather than
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
| P6 | pmOS device package | in progress in [`pmaports-lge-joan`](https://github.com/ShapeShifter499/pmaports-lge-joan) | no |
| P7 | Wi-Fi: WLFW service 69 / `wlanmdsp.mbn` | blocked | yes |
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
| Board DTS (kernel repo) | `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts` |

Assisted-by: Claude-Code
Date: 2026-09-23
Update-scope: README restructured around the 2026-08-10 state; history moved to docs/status-history.md.
