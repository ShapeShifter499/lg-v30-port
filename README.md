# LG V30 (joan, US998) mainline Linux port

Project home for humans and AI agents alike. Anyone picking up a work parcel
starts here — this file is the single source of truth for state and
conventions. **Contributions are welcome via GitHub pull requests and issues**
on the project repos — see [CONTRIBUTING.md](CONTRIBUTING.md):

- this repo — harness, docs, evidence;
- [`linux-lg-v30-joan`](https://github.com/ShapeShifter499/linux-lg-v30-joan)
  (branch `joan/latest-clean-test`) — the kernel;
- [`pmaports-lge-joan`](https://github.com/ShapeShifter499/pmaports-lge-joan)
  (branch `device-lge-joan`) — the postmarketOS device port, kept as a
  pmaports fork so it can become the upstream pmaports merge request.
(Historical docs under `docs/` also mention an internal tracker and an
"internal mirror" used by the original maintainers' agents; those are not
publicly accessible and nothing essential lives only there.)

## Goal

Boot modern mainline Linux (6.x) on Lance's LG V30 **US998**. First userspace
target: postmarketOS. Stretch: AOSP-on-mainline. The phone's daily driver will
be LineageOS 22.2 (Android 15 on downstream 4.4) — the port never touches that
install: test kernels boot tethered (`fastboot boot`) or from the recovery
partition.

Full background: `docs/recon-2026-07-04.md`.
Project history / attribution index: `docs/project-history-and-attribution.md`.
**Mandatory current device-test index:** `docs/test-results/README.md`.
Newest completed device-test packet: `docs/test-results/A183-2026-08-03.md`.
Current host-only source checkpoint: `docs/test-results/A184-2026-08-03-host-only.md`.
Sanitized current continuity source of truth: `docs/test-results/README.md` and
its immutable per-candidate packets.
Current display handoff (both paths): `docs/handoff-2026-07-11-k078-k079-display-two-paths.md`.
Prior Hermes Agent K076/K077 handoff: `docs/handoff-2026-07-11-k076-k077-display.md`.
The earlier K068-K071 and Claude Code K072-K075 handoffs remain historical context.

## Repos and paths (the original maintainers' local layout)

This table documents how the original maintainers arrange things on their own
build host. Treat it as a guideline: replicate it only if you want an
identical setup — any layout works as long as the build/test commands are
adjusted to match.

| What | Where |
|---|---|
| This project (harness, docs) | `~/vibe-coding-projects/coding/lg-v30-port/` |
| Mainline kernel work tree | `~/vibe-coding-projects/coding/linux-mainline-v30/`, active clean tethered-test branch **`joan/latest-clean-test`**; debug branch `joan/latest-kernel` and older refs `lge-joan-bringup` / `joan/bringup-debug` are preserved |
| Device-tested brightness/GPU/touch source | local worktree of `ShapeShifter499/linux-lg-v30-joan`, branch `joan/clean-gpu-brightness-v1`, signed HEAD `3886e860d607` (local/unpushed); A183 device-proved STMFTS input, display/DRM, and direct FD540/freedreno, but exposed stale `max_brightness=251` and left GPU power/suspend open |
| Current host-only brightness correction | local worktree of `ShapeShifter499/linux-lg-v30-joan`, branch `joan/a184-polish`, signed local commit `739bc79d39e8` on `3886e860d607`; restores visible maximum 255 but has no full build/image/device authorization |
| Board DTS | `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts` (first commit `3d3868854`, see its body for design decisions) |
| Downstream reference kernel | `~/vibe-coding-projects/coding/android_kernel_lge_msm8998/` (LineageOS 4.4, **read-only reference — never build or modify**) |
| Downstream joan DTS | `arch/arm64/boot/dts/lge/msm8998-joan/` in the downstream tree |

## Provenance

See [PROVENANCE.md](PROVENANCE.md) for what is original to this project vs
borrowed/derived (and from where), and `docs/project-history-and-attribution.md`
for who did what, when. Kernel branch: [ShapeShifter499/linux-lg-v30-joan
`joan/latest-clean-test`](https://github.com/ShapeShifter499/linux-lg-v30-joan/tree/joan/latest-clean-test).

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

For debug/oracle images built against the `out/initramfs-k023b.cpio.gz`
classifier ramdisk (spin + 90s deliberate reboot, `panic=0`), use
`scripts/tethered-test.sh <boot.img> [timeout_seconds]` to run the full
tethered-boot-and-classify workflow safely (one-client fastboot
discipline, LOS-return classification, PON/bootreason readback). See the
script's own header for its exit-code meanings. After any early reset/panic,
immediately run `scripts/read-pstore-partition.sh` from LineageOS root to pull
the raw pstore partition; mounted `/sys/fs/pstore` can be empty while the raw
partition still contains the mainline ramoops console.

Boot format (from LineageOS BoardConfig): `Image.gz-dtb` appended DTB, base
0x0, pagesize 4096. LG aboot may not support `fastboot boot` — untested;
fallback is flashing the **recovery** partition (never boot) and key-combo
booting it (Vol-Down + Power, release/re-hold Power at the LG logo).

## Procedures

- **SD card filesystem (the pmOS rootfs lives on the microSD).** Runbook:
  `docs/sd-card-fsck-and-recovery.md`; automated helper:
  `scripts/sd-fsck-repair.sh`.
  - Pre-boot check (read-only, no authorization needed):
    `scripts/sd-fsck-repair.sh check` — runs e2fsck 1.47.4 from the pmOS
    initramfs (pushed via adb root, musl loader) read-only against
    `mmcblk0p2`. Use this instead of LineageOS's e2fsck 1.46.2, which
    cannot check `p2` (newer ext4 features; its "still has errors" means
    "could not check", never a result in either direction).
  - Repair (persistent write — Lance must be present and approving):
    `AUTH=yes-i-have-owner-authorization scripts/sd-fsck-repair.sh repair`.
    Trigger: a RAM boot prints "I/O error on the SD card, FSCK repair
    wait timed out" (the 30 s auto-continue from the recovery-patched
    initramfs) — that is a dirty journal, not a dead card. Expect rc 1
    (errors corrected); rc >= 4 means uncorrected/hard errors — card
    replacement/reimage. Orphaned trees (e.g. `/home/user`) land in
    `/lost+found`; restoring them is a persistent-rootfs write and
    needs authorization too.

Assisted-by: Hermes-Agent:deepseek/deepseek-v4-flash
Date: 2026-08-07
Update-scope: SD fsck procedure + script.

## Work parcels

**Claim a parcel by opening a GitHub issue on this repo (or commenting on an
existing one) so work isn't duplicated; deliver via pull request.** Parcels
marked *no-device* are fully doable without the phone. P0 and P5 are complete
(the board boots mainline to userspace via `fastboot boot`).

| # | Parcel | Status | Needs device? | Depends on |
|---|---|---|---|---|
| P0 | Verify kernel build + boot.img packaging | DONE | no | — |
| P1 | Cross-check RPM regulator voltages vs downstream `msm8998-joan-common-pm.dtsi`; fix `msm8998-lge-joan.dts` (currently copied from OnePlus 5) | open | no | — |
| P2 | Extract SW43402 panel data from downstream (`dsi-panel-sw43402*.dtsi`): DSI init sequence, timings, DSC PPS params → `docs/panel-sw43402.md` | open | no | — |
| P3 | DSC-on-MDP5 feasibility verdict: read mainline `drivers/gpu/drm/msm` (mdp5 vs dpu DSC), downstream DSC usage; deliverable = written verdict + recommended display path in `docs/display-path.md` | open | no | — |
| P4 | FTS3670 touchscreen node/driver path | A183 device-proven: probe/input plus bounded multitouch coordinates and owner interaction pass; upstream warning/implementation polish remains | yes, for final acceptance | P1 helps |
| P5 | Device chunk: unlock, LineageOS install, `fastboot boot`, first tethered mainline boot | DONE (2026-07-10: mainline userspace + USB gadget) | — | — |
| P6 | pmOS `device-lg-joan` package skeleton (pmaports layout, deviceinfo, kernel APKBUILD against our branch) | open | no | — |

## Conventions (binding)

- **Commits**: kernel-style subjects (`arm64: dts: qcom: ...`), detailed body
  (what + why), author `Lance <Gero3977@gmail.com>`, trailers per kernel.org
  coding-assistant policy:
  `Signed-off-by: Lance <Gero3977@gmail.com>` +
  `Assisted-by: <harness>:<provider>/<model actually running>` (for example,
  `Hermes-Agent:openai-codex/gpt-5.6-sol`). Never `Co-Authored-By`.
  See [CONTRIBUTING.md](CONTRIBUTING.md) for the full policy.
- **Branches**: small topic branches `joan/<topic>` off `lge-joan-bringup`,
  merged back into `lge-joan-bringup` when the parcel is done. Don't rebase or
  amend another agent's commits.
- **AI attribution on public docs/artifacts**: use the kernel.org-style
  `Assisted-by: <harness>:<provider>/<model>` identity for the harness/model
  actually used, plus the date and update scope where useful. Do not publish
  local agent persona names or private peer IDs. Private/local records and the
  private coordination board may retain persona names for internal continuity.
- **Safety**: nothing in this project flashes, deletes, or modifies the phone
  or any partition without Lance present and approving. Test images are built
  to `lg-v30-port/out/` and go nowhere else. The downstream kernel tree is
  reference-only.
- **State**: when you finish or hand off, update your parcel issue and, if the
  facts here changed, this README (append, don't rewrite history).
- **Candidate closure packets**: after every K/A device test or meaningful
  host-only candidate checkpoint, create `docs/test-results/<candidate>-<date>.md`
  from `docs/templates/candidate-test-closure.md`, update the read-first index,
  push the checked docs commit, mirror the exact result/no-replay/next-action
  block to the shared Nextcloud Deck card, and read both sources back. Except for
  immediate safety recovery, do not start the next experiment before closure.
- **Project history / attribution index**: when a session materially changes the
  project, update `docs/project-history-and-attribution.md` so future agents can
  see who did what and when without reconstructing the entire ledger.
- **Dependency tracking**: any host package install or external source
  download made for this project gets a row in `docs/dependency-tracker.md`
  in the same session, with attribution. Cleanup/removal gets a row too.
- **Kernel change tracking**: every kernel-impacting change must also be entered
  in `docs/kernel-change-ledger.md` before handoff, whether it is a final
  upstreamable commit, bringup-only patch, debug oracle, or rejected experiment.
  Entries need the commit hash or saved patch path, touched files, evidence, and
  status (`upstream-candidate`, `bringup-local`, `debug-only`, `rejected`, or
  `unknown`). Public/PR-ready work must also satisfy
  `docs/public-upstreaming-plan.md`: clean topic commits, detailed rationale,
  verification evidence, no debug-only leftovers, and required trailers.

## Latest status (2026-08-03)

- **Read `docs/test-results/README.md` first.** It is the mandatory compact
  candidate index; detailed handoffs and this README remain supporting history.
- **A183 completed one authorized RAM-only test and its authorization is
  consumed.** Never invoke the A183 runner again. The exact image SHA-256 is
  `44e5f22fed866348d7dc28ac21a9cc2feddede43566795b0cd74deecfa555716`.
- **Touch/input passes on A183.** STMFTS identified the FTS3670 controller,
  registered `/dev/input/event3`, and emitted a 14.476-second bounded multitouch
  stream: 26 contact starts/releases, 978 synchronized reports, X 177..1406 and
  Y 15..2872. Lance reported “Touch seems good.” The SSH wrapper's teardown
  status 255 is recorded separately from the complete positive event payload.
- **Display and direct hardware rendering pass on A183.** The owner-visible UI
  remained usable; A183 itself returned `GL_VENDOR=freedreno` and
  `GL_RENDERER=FD540`; pre/post-EGL dmesg artifacts are byte-identical with no
  matched GPU/DRM/IOMMU/panel fault.
- **Brightness is functionally responsive but its exposed contract fails.** Lance
  reported that the slider worked without a crash. The retained runtime sample
  recorded `brightness=9`, `actual_brightness=9`, and
  `max_brightness=251`; it does not contain raw endpoint-255 telemetry. The
  established owner-visible range is **6–255**; DBV 3 remains internal off.
  K178's 251 ceiling is historical serialization evidence, not the final range.
- **A184 is host-only.** Signed local commit `739bc79d39e8` changes the SW43402
  maximum/comment to 255 while retaining off 3, visible minimum 6, serialization,
  and perceptual mapping. Signed comment-only follow-up `fa041e291644` clarifies
  the mixed A530/A540 firmware roles without changing DT properties. Strict
  diff/style/mapping checks and the focused panel object build pass. No complete
  A184 kernel/image/manifest or phone authority exists.
- **The physical GPU remains Adreno 540.** Upstream A540 deliberately reuses
  packaged `a530_pm4.fw` and `a530_pfp.fw`; owner-extracted `a540_gpmu.fw2`
  and signed LG `a540_zap.*` remain separate local-only inputs. The current tip
  removes all such firmware bytes from tracking and image/package construction
  fails closed when required local inputs are missing. Per maintainer direction,
  the older public Git objects are not history-rewritten by this prospective fix.
- **GPU power and suspend remain open.** A183 is bounded to the sole 257 MHz OPP
  and renders on FD540, but runtime PM stayed active with zero suspended time,
  `vddcx` used a dummy-regulator fallback, devfreq reported transition-accounting
  trouble, sustained-load closure is absent, and suspend/resume was not run.
  Communications remain blocked.
- Exact checkmark packets:
  `docs/test-results/A182-2026-08-02.md`,
  `docs/test-results/A183-2026-08-03.md`, and
  `docs/test-results/A184-2026-08-03-host-only.md`.

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-08-03
Update-scope: A183 runtime closure, A184 host checkpoint, and firmware boundary.

## Prior status snapshot (2026-08-02; superseded by the packets above)

- **A181 recovery is complete, not stuck.** Its one-shot RAM boot reached pmOS
  but failed graphics activation because MSM8998 MMCC was modular with no
  matching module tree. The pmOS-side reboot documented with assistance from
  Claude-Code:claude-fable-5 returned the phone
  to fully booted authorized LineageOS without fastboot recovery or a manual
  restart.
- **A182 directly proves the exact-source display/GPU path.** With MMCC built in,
  MSM DRM initialized, DSI was connected/enabled at 1440x2880, backlight existed,
  A530/A540 firmware loaded, and a direct EGL query returned
  `freedreno` / `FD540` / OpenGL ES 3.1 Mesa 26.1.1 with no precise graphics/GPU
  fault matches.
- **A182 touch failed due to a missed config gate.** Lance reported broken touch;
  no touchscreen input node existed and `CONFIG_TOUCHSCREEN_STMFTS` was disabled.
  K178 had it built in. A183 changes exactly STMFTS `n -> y`, preserves K178's
  driver/binding/touch DT path, and passes host/image qualification. A183 image
  SHA-256 is `44e5f22fed866348d7dc28ac21a9cc2feddede43566795b0cd74deecfa555716`.
  It is not staged, booted, or authorized while Lance is unavailable.
- **Brightness audit: keep the K178 implementation.** Its runtime path is already
  small: monotonic 0..251 mapping, one one-byte LP-mode `WRDISBV`, no diagnostic
  readback, and DPU/DSI exclusion around the command. K178's 180/180 slider
  stress pass remains the device evidence; no speculative caching or rate-limit
  rewrite was added.
- **GPU rendering is real but not full DVFS/power closure.** FD540/freedreno,
  userspace submits, and Phosh rendering are hardware-proven. The clean
  candidate retains only the safe 257 MHz OPP and one runtime-PM hold because GX
  collapse/restore remains broken. Do not describe this as fully power-optimized
  or enable higher OPPs without voltage/CPR/thermal evidence.
- Candidate source `3886e860d607` adds the missing A540 seven-clock binding
  (including `mem_src`) and MSM GPU supply bindings. Full
  `Image.gz modules dtbs`, focused `W=1`, binding/example, compiled joan-DTB,
  config-normalization, image/firmware tests, and keyless Alpine abuild
  `prepare/build` all passed. Two separately authorized one-shot RAM boots then
  produced the scoped A181/A182 results above; no flash, erase, retry, or push
  occurred.
- The local pmaports integration diff is intentionally uncommitted: its current
  public kernel pin predates the panel/GPU candidate. Publish the kernel branch,
  then update `_commit` and checksum atomically. Earlier work assisted by
  Claude-Code:claude-fable-5 completed
  signed kernel/device package builds; preserved `r0`/`r1` APKs prove that path
  worked. This audit's new `3886e860...` APK was not emitted because migration
  retained the old public abuild key but not its private half. No trust
  credential was replaced. The historical packages use older source and are
  not substitutes for an exact-candidate package.
- Exact public closure and current approval-gated artifact manifest:
  `docs/test-results/A183-2026-08-03.md` and
  `out/audit-20260802/a183-mmcc-touch-builtin.manifest.txt`.
- Communications work remains blocked until touch, complete brightness/panel
  behavior, GPU power/performance, and safe suspend/resume are closed or their
  limits are explicitly documented.

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-08-02
Update-scope: Brightness/GPU audit and A181/A182/A183 continuity.

## Prior status (2026-07-28)

- **K178 built-in brightness slider: PASS (RAM boot).** The corrected candidate
  retains the clean `72a8deb11` 6..251 mapping and modeset guard, excludes the
  rejected DBV-parameter experiment, serializes DPU kickoff against panel DCS
  transfers, and disables per-update diagnostic readbacks by default.
- Lance slowly and rapidly exercised the built-in postmarketOS/phosh slider
  while the compositor animated. Brightness tracked mostly in line with the
  slider; the UI stayed responsive with no garbage frames, blackouts, freezes,
  or reboot. All 180 rapid-monitor samples stayed in pmOS, and no DSI-link or
  DPU-kickoff timeout appeared.
- K178 also restores the still-required `msm.k127_no_suspend=1`; it does not fix
  the separate a540 GX power-collapse/restore defect. The test was RAM-only and
  nothing was flashed. Full evidence is in
  `out/boot-joan-k178-slider-gate-k127.test-result.txt` and
  `docs/handoff-2026-07-28-slider-serialisation.md`.

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol
Date: 2026-07-28
Update-scope: K178 brightness-slider result classification.

- **K103 boot discriminator: PASS.** A source-reproducible K102 derivative that
  deletes only `touch-int-default-state/input-enable` completed one RAM-only,
  no-timeout, no-retry `fastboot boot` and reached continuous postmarketOS
  userspace from the microSD. In this controlled pair, the deletion was
  sufficient to eliminate the observed K102 boot failure; the low-level
  mechanism is not yet proven.
- **Touch enablement: FAIL / unresolved.** The ST FingerTipS I2C/OF device was
  instantiated and `stmfts_probe()` ran, but returned `-110`, unwound, and
  registered no touch input device. The next step is an instrumentation-only
  K104, not a combined protocol/IRQ/DT guess.
- Full source/image provenance, transport evidence, inference boundaries, and
  recovery state are in
  [`docs/handoff-2026-07-21-k103-input-enable-discriminator.md`](docs/handoff-2026-07-21-k103-input-enable-discriminator.md).
- The phone was gracefully recovered to fully booted authorized LineageOS.
  Nothing was flashed or pushed. Do not rerun K103; K101 remains quarantined.

The status below is retained as the 2026-07-11 historical snapshot.

## Current status (2026-07-11)

- **Latest checkpoint:** mainline reaches USB userspace, UFS/microSD, postmarketOS
  headless operation, and active DRM/fb0 at 1440x2880@60. M1-M3 are done;
  built-in display M4 remains in progress and physically black/off. See
  `docs/handoff-2026-07-11-k076-k077-display.md`.
- K062's MSM8998 MDSS identity-domain policy removed the fatal display-SMMU
  handoff gate. K065 fixed the 10nm DSI VCO factor-of-two calculation, and K067
  added the real DSI VDD rail. DRM now maps a fresh framebuffer IOVA and active
  DMA0 latches it, ruling out stale boot-splash addressing as the leading
  post-DRM failure.
- K076 proved the late `/4` PLL output-divider rewrite is caused by the
  half-rate `byte_intf_clk` request propagating through mainline's shared
  `byte0_clk_src` parent. K077 suppressed that one request as a discriminator:
  the main pixel/byte clocks became correct and DRM remained active, but the
  interface clock was then incorrectly full-rate and the panel remained
  physically black/off. The source-correct next clock change is to model the
  dedicated MSM8998 byte-interface `/2` divider at MMCC register `0x237c`
  (and byte1 at `0x2380`), not to retain K077's skip. Full-rate DSI clocks alone
  are therefore insufficient; after the divider is represented correctly,
  investigate panel readback/BTA and command-mode TE/kickoff behavior.
- Historical path: K068 confirmed a black/off screen; parent-enabling the RCGs
  removes their update warnings but prepares the PLL with stale divider state
  and causes lock/clock-balance failures. K069's narrow `/2` pre-lock override
  did not persist. K070 found correct saved divider state but
  `vco_current_rate=0`. K071's recalc state assignment was worse and collapsed
  the final DSI0 clock hierarchy to 0 Hz. K072's one-time seed later restored
  PLL locking without that global recalc mutation.
- Phone is recovered to fully booted authorized LineageOS. Every K060-K077 test
  was RAM-only `fastboot boot`; no partition was flashed. Kernel commits and
  documentation are local/unpushed.

### Earlier reset-hunt history

- **CONFIRMED FIX: `anoc1_smmu` skip-reset eliminates the TZ Config/MM-NoC
  fault.** `anoc1_smmu` (`iommu@1680000`, aggregator-NoC IOMMU) has zero
  `iommus=` consumers anywhere in mainline's `msm8998.dtsi` and no
  `clocks=` property, yet defaults `status = "okay"`, so mainline's
  arm-smmu-v2 driver always runs its full global reset on it
  (`arm_smmu_device_reset()`: clears sGFSR, forces every SMR
  invalid/every S2CR to bypass, invalidates the TLB). Downstream
  `msm-arm-smmu-8998.dtsi` marks this exact block (and all five msm8998
  SMMU-v2 instances) `qcom,skip-init` + `qcom,register-save`: TZ/XBL
  already owns and configured it, and downstream's driver deliberately
  never resets it. A debug-only kernel patch
  (`out/k030-skip-smmu-reset-debug.patch`, gates the reset behind a
  new `debug-skip-reset` DT boolean) tagged onto `&anoc1_smmu`
  alone eliminated the specific TZ NoC fault that had blocked every
  session back to K022: bootreasoncode moved from the
  `LGE_RB_MAGIC|LGE_ERR_TZ` crash family (`0x6D630309` Config NoC /
  `0x6D630306` MM NoC) to a plain, non-magic `0x20`
  (`UNDEFINED_CRITICAL_ERROR`). Device-tested (K030).
- **K031 rejected the broader fix.** Tagging all five SMMUs (matching
  downstream's blanket policy) gave an identical result to K030's
  anoc1-only patch — no additional benefit — while carrying a real
  correctness risk for wifi/GPU/audio's own SMMUs once their real
  consumers attach domains (untested by the spin-only classifier). Since
  K030 (their reset left normal) and K031 (their reset skipped) are
  otherwise identical and gave the *same* result, this also rules out
  those four SMMUs' reset behavior as a factor in the residual fault.
  **Prefer K030's narrower patch.**
- **K032 corrected the K027-era cmdline hypothesis.** The
  `clk_ignore_unused pd_ignore_unused` retention in place since K027 was
  never load-bearing — plain default cmdline gives an identical result
  once the anoc1 fix is in place. `docs/k028-conf-noc-sweep-hypothesis-
  2026-07-07.md`'s clock-sweep theory was a coincidental correlation, not
  a cause. **Confirmed clean baseline: full untouched joan DTS +
  `&anoc1_smmu { debug-skip-reset; };` + plain default cmdline.**
- **K033/K034 narrowed the residual fault to SoC core/firmware.**
  Stripping every removable board peripheral (K033, same list as K023e:
  `usb3`, `qusb2phy`, `ufshc`, `ufsphy`, `wifi`, `pm8005_regulators`) and
  disabling the APSS watchdog node outright (K034, a different
  manipulation than K024's kernel-side pet) both still hit the identical
  `0x20` reset. Neither peripherals nor the non-secure APSS watchdog are
  the residual cause. A full LOS dmesg pull (no new reboot needed) found
  downstream's own boot chain logs `0x20` as `"not handled, defaulting to
  Normal Boot"` — it may not be a live TZ-detected code at all, possibly
  just IMEM's resting state once no detector writes to it.
- **K035 (IMEM seed oracle): device photo reveals MM_NOC is still the
  real fault, and the test itself likely crashed the firmware.**
  Reintroduced Claude Code's 2026-07-06 IMEM-oracle initcall
  (`drivers/soc/qcom/joan_imem_oracle.c`) on the confirmed K030 baseline
  to write a distinctive seed (`0x6D6303EE`) to the restart-reason offset
  before the reset. `fastboot boot` succeeded, but LineageOS never
  returned; the phone landed in an unfamiliar USB mode
  (`1004:6340`) first thought to be a USB 3.0 charging issue (it briefly
  was, on an earlier pass, and moving to USB 2.0 fixed that) — but this
  time Lance photographed the actual screen, revealing LG's UEFI-level
  crash handler (never seen before in this project). Transcribed at full
  photo resolution: an early-boot `tzbsp_reason: 0x6d630301`
  (TZ_NON_SEC_WDT) followed later in the same boot by **`tzbsp_reason:
  0x6D630306` — the same MM_NOC fault first found in K027** — then a
  firmware `DXE_ASSERT!: [ResetRuntimeDxe] String.c (199)` NULL-pointer
  crash and entry into Sahara mode (why neither `adb` nor `fastboot`
  could reach it; recovered with a plain Volume-Down hold, per the
  screen's own instructions).
  **Conclusions:** (1) the residual fault K033/K034 saw as a generic
  Android-property `0x20` was almost certainly this same MM_NOC value,
  mis-reported/genericized by Android's own property layer rather than
  a new third fault — their peripheral/watchdog eliminations still
  stand, just against MM_NOC specifically, not an unnamed one; (2) the
  DXE_ASSERT/Sahara crash is most likely a side effect of the IMEM
  write landing near a string/pointer structure XBL's own
  `ResetRuntimeDxe` also uses — this exact firmware crash never
  appeared in any earlier test, including several that also hit
  MM_NOC/Config NoC resets, and the only new variable this time was
  that write. **Do not reuse a raw, unverified IMEM write at this offset
  again.** The IMEM-oracle addition has been reverted from the kernel
  tree (the confirmed-good `anoc1_smmu` skip-reset patch remains).
  Full detail: `docs/kernel-change-ledger.md` (K035 entries),
  `docs/handoff-2026-07-07-k029-onion-peel.md`.
- **New reusable tooling:** `scripts/tethered-test.sh` extracts the full
  tethered-boot workflow (one-client fastboot discipline, LOS-return
  classification, PON/bootreason readback) into a single committed,
  documented script, replacing this week's ephemeral per-test copies so
  future sessions/agents don't re-derive it from scratch. It also
  explicitly distinguishes "device absent" / "unfamiliar USB state, stop"
  / "still fastboot, probably just slow" outcomes.
- **K036 (sibling MMSS-NoC-bridge clocks marked critical): tested,
  REJECTED — and it corrects the whole line of attack.** `gcc_mmss_noc_
  cfg_ahb_clk` is already `CLK_IS_CRITICAL` with an upstream comment
  documenting a crash in exactly our RPM configuration; three sibling
  clocks in the same register bank (`gcc_mmss_sys_noc_axi_clk`,
  `gcc_mmss_qm_ahb_clk`, `gcc_mmss_qm_core_clk`) lacked the same
  protection. Marking them critical too made no difference — still
  resets, still `0x20`. More importantly: comparing K027 (clock
  retention on) against K032 (retention off, after the anoc1 fix), both
  of which hit MM_NOC identically, shows the **entire "unclaimed clock
  gated by the late sweep" theory class cannot explain MM_NOC** — not
  just these three clocks. Reverted from the kernel tree (patch kept at
  `out/k036-mmnoc-critical-clocks.patch` for reference).
- **Post-reset observability breakthrough (2026-07-08): raw pstore works if
  read from the block partition, not from mounted `/sys/fs/pstore`.** The first
  256 KiB read of `/dev/block/platform/soc/1da4000.ufshc/by-name/pstore` from
  LineageOS root preserved K042's mainline ramoops console. This overturned the
  old conclusion that pstore was useless and showed K042 died at ~0.073s in
  TLMM/GPIO registration before it could test the SMMU cfg-probe hypothesis.
  Details: `docs/observability-tlmm-gpio-2026-07-08.md`.
- **K042 reclassified: superseded/invalid SMMU oracle, not a valid SMMU
  rejection.** The K042 RAM-only image did return to LineageOS early, but raw
  pstore later proved the immediate failure was an MSM8998 pinctrl/gpio abort
  (`gpiochip_add_data_with_key()` / `msm_gpio_get_direction()`), not the SMMU
  cfg-probe code under test. Keep the K042 patch as preserved debug evidence,
  but do not cite it as ruling out SMMU cfg-probe.
- **K043-K050 TLMM/GPIO narrowing produced a current DTS-only candidate.**
  Disabling TLMM (K043), skipping `msm_gpio_init()` (K044), and disabling
  `get_direction` readback (K047) all survived the classifier window. Pstore
  for K046/K048/K049 identified protected/inaccessible GPIO direction reads at
  GPIO49, GPIO50, and GPIO81. K050, adding
  `gpio-reserved-ranges = <0 4>, <49 4>, <81 4>;`, survived to the deliberate
  reboot window (`t+123s`, 111s after handoff). Candidate patch:
  `out/k050-clean-candidate-gpio-reserved-ranges-2026-07-08.patch`.
- **Observability tooling/caution:** use `scripts/read-pstore-partition.sh`
  immediately after failed RAM boots to capture the raw pstore partition.
  `/sys/kernel/debug/tzdbg` exists on LineageOS, but reading its contents caused
  adb/device disappearance during this session. Do not casually
  `cat /sys/kernel/debug/tzdbg/*`; prefer raw-pstore capture first.
- **Next device/software action:** K050 is source-supported for GPIO81..84 by
  multiple upstream MSM8998 DTS files, but GPIO49..52 is currently
  pstore/device-proven rather than source-obvious. Find stronger source evidence
  for `<49 4>` or decide that joan firmware behavior is enough, then turn K050
  into a cleaned candidate and run one RAM-only confirmation test before public
  push.

## Previous status (2026-07-06)

- **P5/debug continued — latest upstream still reboots before debug output.**
  Hermes Agent rebased the joan debug stack onto fetched upstream `origin/master`
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
- **Reset source remains unresolved, but narrowed.** Hermes Agent tested the obvious
  downstream `SEC_WDOG_DIS` translations plus discriminators. `panic=30` and
  disabling the APSS watchdog DT node did **not** shift the reset window; a PSCI
  timing oracle at `qcom_scm_probe()` proved SCM probe is reached early enough.
  A downstream LineageOS runtime check showed the downstream `SEC_WDOG_DIS`
  sysfs path itself fails with `0x42000107 ret=-2`, so it is not a known-good
  survival path. Clean APSS WDT takeover tests matching downstream bark/bite/pet
  behavior, including EN=3 for `qcom,wakeup-enable`, still rebooted to LineageOS
  before mainline USB/diag appears.
- **Latest new-path tests also failed.** Hermes Agent tested single-core boot
  (`maxcpus=1`, image sha256
  `5bd01b0a987563027abbb968810b1b796201cbffb32e99effa4fc95d672c93e8`,
  LineageOS return `t+29.5s`), CPU idle disabled (`cpuidle.off=1 nohlt`, sha256
  `3f4b26656dc1af381128aa211787297ce85808e638287a1c21f7c550b5f9955d`,
  return `t+45.8s`), and a debug-only downstream high-memory reservation patch
  (`out/latest-highmem-reserve-test-2026-07-06.patch`, image sha256
  `c9f4545b790084dd82b139109dc29dffa516f1c3a17620a003db3b6241a886a6`,
  return `t+29.4s`). None exposed mainline USB/diag. Full table and
  next-analysis notes are in `docs/bringup-debug-state-2026-07-06.md`.
- **Secure-liveness diff follow-up: DLOAD-off argument shape is not the fix.**
  Downstream `msm-poweroff.c` on LGE builds defaults `download_mode=0` and its
  `pure_initcall` issues `set_dload_mode(0)`, which sends SCM boot command
  `SCM_DLOAD_CMD` (`0x10`) with args `(0, 0)`. Mainline `qcom_scm` used the same
  command but represented the off request as args `(0x10, 0)`. Hermes Agent tested a
  debug-only patch changing mainline's off request to downstream's `(0, 0)`
  shape (`out/latest-dload-off-argshape-test-2026-07-06.patch`; image
  `out/boot-joan-latest-dload-off-argshape.img`, sha256
  `423d0c7f306a0d1617ade6577c8cb012df71cda6d6f8a08ab731dc4e79a26457`).
  `fastboot boot` succeeded but no mainline USB/diag appeared; LineageOS adb
  returned at `t+44.3s` and the post-reset PON log again showed SID0
  `PS_HOLD`. The patch was saved, reverted, and the kernel was rebuilt clean.
- **QSEE/QSEEOS log-buffer ping also failed as a survival oracle.** Hermes Agent then
  matched downstream `tz_log.c`'s ARMv8 `SCM_QSEEOS_FNID(1, 6)` QSEE log-buffer
  registration as a debug-only qcom_scm probe call using a 32 KiB TZ memory
  buffer (`out/latest-qsee-logbuf-oracle-2026-07-06.patch`; image
  `out/boot-joan-latest-qsee-logbuf.img`, sha256
  `6a99c6f2c653e21d2cbba2df7ad2d392dbbcc40f0db7fef63efd599d57b7eb93`).
  RAM-only `fastboot boot` succeeded, but no mainline USB/diag appeared;
  LineageOS adb returned at `t+52.2s`, and PON evidence still showed SID0
  `PS_HOLD`. The patch was saved, reverted, and the kernel rebuilt clean.
- **RPM `rpm_requests` reachability oracle did not produce survival.** Downstream
  brings APSS-RPM communication over GLINK up early (`msm_rpm_dev_probe`,
  `rpm_requests` around `0.332s` in downstream dmesg). Mainline already has
  `qcom,glink-rpm` / `qcom,glink-smd-rpm` nodes and built-in RPM/SMEM/SMP2P
  support, so Hermes Agent tested a debug-only timing oracle in
  `drivers/soc/qcom/smd-rpm.c`: if the `rpm_requests` rpmsg driver probes on
  `lge,joan`, wait 4 seconds then issue PSCI `SYSTEM_RESET`.
  (`out/latest-rpm-rpmsg-reachability-oracle-2026-07-06.patch`; image
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
  regulator child nodes. Hermes Agent tested a minimal debug-only RPM write in
  `drivers/soc/qcom/smd-rpm.c` after `rpm_requests` probe: send KVP `bobm=2` to
  resource `BOBB:1` in active and sleep sets
  (`out/latest-rpm-bob-mode-oracle-2026-07-06.patch`; image
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
  boot/always-on flags. Hermes Agent tested a minimal DT-only oracle in
  `arch/arm64/boot/dts/qcom/msm8998-lge-joan.dts` that changed `vreg_l19a_3p0`
  to 3.3 V and marked it `regulator-boot-on`/`regulator-always-on`
  (`out/latest-rpm-l19-always-on-oracle-2026-07-06.patch`; image
  `out/boot-joan-latest-rpm-l19-always-on.img`, sha256
  `84134c0d71c7f7eafae9e6a268c50302238a002b6c11c229baa6b52a6ee96e04`).
  RAM-only `fastboot boot` succeeded, but no mainline USB/diag appeared;
  LineageOS adb returned at `t+57.8s`, and PON evidence again showed SID0
  `PS_HOLD`. This minimal DT-backed default vote is not sufficient by itself,
  though it keeps broader downstream PM/RPM regulator parity worth testing.
  The patch was saved, reverted, and the kernel rebuilt clean.
- **Broader DT-backed PM/RPM overlay oracle also failed.**
  Hermes Agent tested a one-bundle downstream PM overlay parity oracle through the
  existing mainline RPM regulator framework: `l18` fixed at 2.704 V and
  `regulator-boot-on`, `l19` fixed at 3.3 V with boot/always-on, and `bob` fixed
  at 3.312 V with boot/always-on (`out/latest-rpm-pm-overlay-oracle-2026-07-06.patch`; image `out/boot-joan-latest-rpm-pm-overlay.img`, sha256
  `de729e6eff09e997de15bdfb0fcf29890e86765228d691f5bb1ca1e185806365`). RAM-only `fastboot boot` succeeded, but no mainline USB/diag
  appeared; LineageOS adb returned at `t+30.6s` after fastboot and PON evidence
  again showed SID0 `PS_HOLD`. This broader DT-backed PM/RPM default-vote bundle
  is not sufficient and does not preserve the longer timing seen with the raw
  BOB-mode oracle. The patch was saved, reverted, and the kernel rebuilt clean.

- **TCSR DLOAD/restart-cookie oracle also failed.**
  Hermes Agent compared downstream's MSM8998 restart/IMEM setup and found that
  downstream exposes `qcom,msm-imem@146bf000` plus a `qcom,pshold` fallback
  `tcsr-boot-misc-detect` resource at `0x1fd3000` (`tcsr_regs_2 + 0x13000`),
  while mainline MSM8998 had no equivalent DLOAD cookie phandle. The oracle added
  `qcom,dload-mode = <&tcsr_regs_2 0x13000>` to mainline SCM so
  `qcom_scm_set_download_mode(0)` clears the same TCSR boot-misc DLOAD bits
  (`out/latest-tcsr-dload-cookie-oracle-2026-07-06.patch`; image `out/boot-joan-latest-tcsr-dload-cookie.img`, sha256 `0ba46735f6f6fac182f3de3f67fe46f5c60c26948be7b1193f7c7147b48645dd`). RAM-only `fastboot boot`
  succeeded, but no mainline USB/diag appeared; LineageOS adb returned at
  `t+55.5s` from test start, and PON evidence again showed SID0 `PS_HOLD`. This
  TCSR DLOAD/restart-cookie route is not sufficient as a standalone liveness
  fix. The patch was saved, reverted, and the kernel rebuilt clean.


- **PM8998 PON S3 source/debounce oracle also failed.**
  Hermes Agent compared downstream joan PMIC/PON setup and found an unsupported
  downstream delta: PM8998 PON programs `qcom,s3-debounce = <32>` and
  `qcom,s3-src = "kpdpwr-and-resin"`, while upstream `qcom-pon` only handles
  reboot-mode spare bits and child population. The DEBUG-ONLY oracle added a
  minimal `qcom-pon` S3 source/debounce programming path plus a joan
  `&pm8998_pon` override, and verified `CONFIG_POWER_RESET_QCOM_PON=y`
  (`out/latest-pon-s3-oracle-2026-07-06.patch`, sha256 `e8dfba3949f4ace1d678ed94ce7e254287197ba4c6ee0d6368d4efa642dc051d`; config `out/latest-pon-s3-oracle-config-2026-07-06.txt`, sha256 `bababe3d52ff1bd1e7b6ede056c8986696260024010f38ab56696039b0bb193c`;
  image `out/boot-joan-latest-pon-s3-oracle.img`, sha256 `2c83d4782aa60564c840efe5122ebfeb9aa30f8e0aea8bab10fc7d70f6fb2c31`). RAM-only `fastboot boot` succeeded
  (`Sending`/`Booting` OKAY, total `5.510s`), but no mainline USB/diag appeared;
  LineageOS adb returned at `t+30.5s`, and post-reset PON evidence again showed
  SID0 `PS_HOLD`. The downstream PON S3 source/debounce delta is not sufficient
  as a standalone liveness fix. The patch was saved, reverted, and the kernel
  rebuilt clean (`out/boot-joan-latest-clean-post-pon-s3-oracle.img`, sha256 `7d87765d96df926cac538563dcbe1989f8990d9b784b1c0163926f5cb5f0b0ef`).


- **PM8998 PON reset-sequence/S1/S2 oracle also failed.**
  Hermes Agent then tested the next fuller downstream PON delta: in addition to the S3
  source/debounce values, downstream joan disables S2 reset on `pon_1`/`pon_2`
  and enables `pon_3` (`KPDPWR_N AND RESIN_N`) with `qcom,s1-timer = <6720>`,
  `qcom,s2-timer = <2000>`, and `qcom,s2-type = <0x08>`
  (`PON_POWER_OFF_DVDD_HARD_RESET`). The DEBUG-ONLY oracle added a minimal
  upstream `qcom-pon` reset-sequence programming path and joan DT child nodes
  (`out/latest-pon-reset-seq-oracle-2026-07-06.patch`, sha256 `588264cfb140c0c307a57b8898f5c1c77bf8fa623da32e68ffaa7ce66f9f552c`; config `out/latest-pon-reset-seq-oracle-config-2026-07-06.txt`, sha256 `bababe3d52ff1bd1e7b6ede056c8986696260024010f38ab56696039b0bb193c`;
  image `out/boot-joan-latest-pon-reset-seq-oracle.img`, sha256 `a0c0e2b6448981798d5cc5b03a4804504caaedff7705a896a42883d86786ee12`). RAM-only `fastboot boot` succeeded
  (`Sending`/`Booting` OKAY, total `5.522s`), but no mainline USB/diag appeared;
  LineageOS adb returned at `t+57.6s` host-script time (`~46.3s` after the
  fastboot command returned), and post-reset PON evidence again showed SID0
  `PS_HOLD`. The fuller downstream PM8998 PON reset-sequence delta is not
  sufficient as a standalone liveness fix. The patch was saved, reverted, and
  the kernel rebuilt clean (`out/boot-joan-latest-clean-post-pon-reset-seq-oracle.img`, sha256 `d543f234ab848f2de12191eca3cf2df2aa87b04711e4665564da93f5cf57f418`).


- **CPU/Kryo SCM errata comparison produced no boot oracle.**
  Hermes Agent compared downstream `drivers/soc/qcom/scm-errata.c` against mainline.
  Downstream has an optional debugfs/hotcpu helper for Kryo errata command `0x12`
  (`E74/E75` enable arg `0x1`, `E76` disable arg `0x100`), but joan defconfigs
  do not enable `CONFIG_QCOM_SCM_ERRATA`, and the helper does not apply itself
  to already-online boot CPUs at init. This is not active downstream default boot
  parity, so no RAM-boot oracle was built. Status artifact:
  `out/kryo-scm-comparison-2026-07-06.txt`.

- **K025 secure-interface archaeology produced no new boot oracle.**
  Hermes Agent followed Claude Code's session-2 handoff and compared downstream
  `watchdog_v2.c`, QSEECOM probe/listener/region paths, `qsee_ipc_irq_bridge`,
  joan defconfigs, and current mainline QSEECOM. Result: the obvious candidates
  were either already tested (`SEC_WDOG_DIS`), already mirrored by mainline
  (QSEECOM version query), inactive on downstream joan defaults
  (`QSEOS_APP_REGION_NOTIFICATION`, skipped because MSM8998 sets
  `qcom,appsbl-qseecom-support`), dump-only (`SCM_SET_REGSAVE_CMD` register-save
  setup), or ordinary IRQ/device plumbing. No speculative RAM-boot oracle was
  built. Status artifact: `out/secure-interface-archaeology-k025-2026-07-06.txt`,
  sha256 `f1a47398089fd7640179a042a8f3016005c3526b5d498fad58cbed5f4f06b630`.

- **K026 LGE IMEM default restart-reason write did not fix survival, but exposed a TZ-class bootreason.**
  Hermes Agent reused Claude Code's debug-only `joan/imem-oracle` commit `f0d368d28`
  because it exactly matches downstream `lge_handle_panic` early IMEM parity:
  write `LGE_RB_MAGIC | LGE_ERR_TZ` (`0x6d630300`) to IMEM restart_reason at
  `0x146bf000 + 0x65c`. It was rebuilt with the safer K023 `panic=0` null-init
  classifier (`out/boot-joan-imem-k026.img`, sha256
  `ccf08dbea0e889fa11404335d423e46e5078f37883469234694aff4d3939d035`).
  RAM-only `fastboot boot` succeeded (`Sending`/`Booting` OKAY, total `5.513s`),
  but no mainline USB/survivor beacon appeared; LineageOS adb returned at
  `t+49.1s`. Post-reset PON still showed SID0 `PS_HOLD`, while the returned
  downstream kernel reported `androidboot.product.lge.bootreasoncode=0x6D630309`
  / `LGE BOOT REASON: 0x6d630309`. That decodes as LGE magic + TZ class +
  undocumented subreason `0x09`; it is **not** the named TZ non-secure watchdog
  bark (`0x3a`) or thermal secure bite (`0x3b`). Artifact:
  `out/lge-imem-k026-result-2026-07-06.txt`.


- **K027 decoded the K026 bootreason as TZ Config NoC error; clk/power-retention image is built but not validly device-tested.**
  Public older LG/QCOM `reboot_reason.h` from the bullhead msm kernel defines
  `LGE_ERR_TZ_CONF_NOC_ERR = 0x0009`, so K026's `0x6D630309` decodes as
  `LGE_RB_MAGIC | LGE_ERR_TZ | LGE_ERR_TZ_CONF_NOC_ERR`: a TrustZone Config
  NoC error. Hermes Agent preserved that public header as
  `out/k027-public-bullhead-reboot_reason.h` (sha256
  `90e24ee46dfedef922c02a55f492b01af460bbbdae1a1c9c3bd40e4fdb8b0355`).
  Downstream MSM8998 has legacy `msm_bus`/NoC/BIMC vote plumbing; mainline joan
  has no MSM8998 ICC provider/votes. A cmdline-only K027 discriminator was built
  with `panic=0 ignore_loglevel clk_ignore_unused pd_ignore_unused` as
  `out/boot-joan-clkpd-k027.img` (sha256
  `60f5484be2aaa8616681dd09130b47decc8684bf6d1e3feb96df2fc90f08bb0e`), but the
  device attempt is **inconclusive**: no fastboot `Sending`/`Booting` OKAY was
  captured, normal-user fastboot hit permissions/timeout, and the phone then
  disappeared from adb/fastboot/USB for a 224s passive observation window. Do not
  treat K027 as rejected or fixed until Lance physically recovers the phone and
  the image is retried with one-client sudo-fastboot discipline. Artifact:
  `out/k027-conf-noc-decode-and-clkpd-attempt-2026-07-06.txt`.

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
  the maintainers' build host — if `arch/arm64/boot/Image.gz` is missing, rerun the build line
  above. Test-image pipeline untested until the kernel image exists (P0).
- Phone not yet confirmed/connected; P5 blocked on Lance.
- Toolchain installed on the maintainers' build host: `aarch64-linux-gnu-gcc` 16.1,
  `android-tools` (adb/fastboot/mkbootimg), `dtc`. `dtschema` NOT installed, so
  `CHECK_DTBS=y` doesn't work yet — install it if you want binding checks.

---
Assisted-by: Claude-Code:claude-fable-5
Date: 2026-07-04

Update-scope: P0 completion status
Assisted-by: Claude-Code:claude-fable-5
Date: 2026-07-05

Update-scope: PM8998 PON S3 oracle result
Assisted-by: Hermes-Agent:openai-codex/gpt-5.5
Date: 2026-07-06

Update-scope: Kryo SCM errata comparison
Assisted-by: Hermes-Agent:openai-codex/gpt-5.5
Date: 2026-07-06

Update-scope: K025 secure-interface archaeology comparison
Assisted-by: Hermes-Agent:openai-codex/gpt-5.5
Date: 2026-07-06

Update-scope: K026 LGE IMEM default restart-reason oracle
Assisted-by: Hermes-Agent:openai-codex/gpt-5.5
Date: 2026-07-06

Update-scope: K027 CONF_NOC decode and inconclusive clk/power-retention attempt
Assisted-by: Hermes-Agent:openai-codex/gpt-5.5
Date: 2026-07-06
