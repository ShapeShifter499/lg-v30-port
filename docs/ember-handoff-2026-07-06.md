# Ember handoff — LG V30 (`joan`) latest-kernel mainline bringup

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

## TL;DR

The LG V30 (`joan`, US998) mainline bringup is still blocked by an early controlled reset before mainline USB/mass-storage/diag diagnostics appear.

The best current interpretation remains:

- the phone reaches early mainline successfully;
- the reset returns to LineageOS through a controlled PMIC/secure-side `PS_HOLD` path;
- many plausible first-second liveness handshakes have now been rejected;
- continue with one concrete downstream-vs-mainline early state delta at a time;
- do not retry the rejected oracles without genuinely new evidence.

Current safe baseline:

- Kernel repo: `/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30`
- Kernel branch: `joan/latest-clean-test`
- Kernel base: `origin/master` `8cdeaa50e` (`Linux 7.2-rc2`)
- Kernel state at handoff: clean, four clean DTS commits ahead of upstream
- Harness/docs repo: `/home/kumo02/vibe-coding-projects/coding/lg-v30-port`
- Harness latest commit before this handoff update: `196e97f docs: record joan Kryo SCM errata comparison`

Use these current source-of-truth files first:

- `docs/kernel-change-ledger.md`
- `docs/bringup-debug-state-2026-07-06.md`
- `docs/2026-07-06_lg-v30-reset-cause-PS_HOLD.md`
- `docs/public-upstreaming-plan.md`
- this file: `docs/ember-handoff-2026-07-06.md`

## Binding safety rules

Unless Lance explicitly changes them:

- Do not flash.
- Do not write phone storage.
- Use RAM-only `fastboot boot` only.
- Lance must be physically present for device work.
- Enter fastboot via `adb reboot bootloader`.
- Use exactly one fastboot client at a time.
- Avoid `fastboot getvar`; it previously wedged LG aboot.
- If the monitor sees LineageOS adb return, classify immediately and stop waiting.
- Keep test images under `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/out/`.
- Report any package installs. Aurel installed none in this batch.

Fastboot script precheck notes:

- Prefer `pgrep -a -x fastboot` for existing fastboot clients.
- A `ps | grep [f]astboot` check inside a heredoc command can false-positive on the parent shell command text.
- Do not probe with `fastboot getvar`; use `fastboot devices` only when needed and bound the call.

## Current clean kernel branch

Kernel path:

```text
/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30
```

Branch:

```text
joan/latest-clean-test
```

Base:

```text
8cdeaa50e Linux 7.2-rc2
```

Carried commits:

```text
25a391c94 arm64: dts: qcom: add initial LG V30 (joan) device tree
a19ca9204 arm64: dts: qcom: msm8998-lge-joan: match downstream ramoops layout
7c906e841 arm64: dts: qcom: msm8998-lge-joan: reserve LG firmware-owned memory
0d7df4134 arm64: dts: qcom: msm8998-lge-joan: add APSS watchdog node
```

This branch intentionally excludes the debug-only breadcrumb commit from `joan/latest-kernel` because that branch changes timing and is not public/PR-ready.

## Latest known device/host state

At Aurel handoff time:

- Phone is back in LineageOS.
- adb serial: `LGUS9986e606d55`
- adb user: non-root shell (`uid=2000(shell)`)
- No fastboot device present.
- No fastboot clients running.
- Kernel repo clean on `joan/latest-clean-test`.
- Harness repo clean before this handoff rewrite, at `196e97f`.
- No packages installed.
- No flashing and no phone-storage writes were performed.

## Commit attribution convention

Use Lance’s required kernel.org / Linux Foundation AI-assisted trailer style.

For Lance + Ember commits:

```text
Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:<actual Ember model>
```

For Aurel/Hermes docs already written:

```text
Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Hermes:gpt-5.5
```

Why:

- `Signed-off-by` is Lance’s human DCO/kernel-style certification.
- `Assisted-by` records AI/tool assistance using the kernel.org-style `Assisted-by: AGENT_NAME:MODEL_VERSION` convention.
- Do not use `Co-Authored-By` for AI assistance.
- Never add an AI `Signed-off-by`; the AI is not the legal DCO certifier.

## Current evidence headline: PS_HOLD reset

Post-reset LineageOS/PON evidence repeatedly reports a controlled PMIC/secure-side `PS_HOLD` reset, not a normal Linux panic or simple APSS watchdog case.

Representative evidence:

```text
PMIC@SID0 Power-on reason: Triggered from Hard Reset and 'cold' boot
PMIC@SID0: Power-off reason: Triggered from PS_HOLD
PM: 0: PON=0x21:PON1:HARD_RESET: POFF=0x2:PS_HOLD: FAULT1=0x40:UVLO
lge.bootreason=NORMAL / bootreasoncode=0x20
```

Interpretation:

- Hardware-visible post-reset state looks like deliberate `PS_HOLD`.
- It is not explained by PMIC keypad fault, PMIC watchdog, thermal bite, ordinary Linux panic, simple APSS watchdog programming, cpuidle, secondary CPU bringup, or simple XPU/high-memory allocation.

## Rejected / de-prioritized paths

Do not repeat these as standalone tests unless there is new evidence that changes the premise.

### Secure watchdog / SCM disable path

Tested:

- mainline `qcom_scm_probe()` variants;
- early raw SMC variants;
- exact downstream function ID `0x02000107`;
- SMCCC function ID `0x42000107`;
- enable args `0` / `1`;
- multi-convention raw SMC spray;
- downstream LineageOS runtime sysfs disable path.

Results:

- None survived to mainline USB diagnostics.
- Multi-convention spray shortened the host return window to about `~30s`, so treat it as harmful/noisy.
- Downstream LineageOS itself reports:

```text
scm_call failed: func id 0x42000107, ret: -2
Failed to deactivate secure wdog
```

Conclusion: `SEC_WDOG_DIS` is not a known-good survival path on this device/TZ firmware.

### Panic / APSS watchdog / timing discriminators

Rejected:

- `panic=30`;
- disabling the APSS watchdog DT node;
- downstream-style APSS WDT petting;
- APSS WDT `EN=3` / wakeup-enable style behavior.

Important positive fact:

- PSCI reset oracle at `qcom_scm_probe()` returned around `~29.7s`, proving SCM probe is reached early enough to run before the normal reset window.

Conclusion: the reset does not look like ordinary Linux panic, mainline `qcom_wdt` misprogramming, missing APSS WDT petting, or SCM probe being too late.

### Latest-clean CPU / idle / high-memory discriminators

Rejected:

- `maxcpus=1`: returned around `t+29.5s`; no mainline diagnostics.
- `cpuidle.off=1 nohlt`: returned around `t+45.8s`; no mainline diagnostics.
- downstream high-memory secure/shared pool no-map reservation: returned around `t+29.4s`; no mainline diagnostics.

Conclusion:

- Not simply secondary CPU bringup / Kryo errata.
- Not generic PSCI/cpuidle idle.
- Not simply early allocator use of those downstream high-memory ranges.

### DLOAD / restart-cookie / QSEE / RPM / regulator oracles

Rejected standalone oracles:

1. DLOAD-off SCM argument shape
   - Patch: `out/aurel-latest-dload-off-argshape-test-2026-07-06.patch`
   - Image: `out/boot-joan-latest-dload-off-argshape.img`
   - Result: fastboot OK, no mainline diagnostics, LineageOS returned at `t+44.3s`, post-reset `PS_HOLD`.
   - Conclusion: downstream `(0, 0)` DLOAD-off arg shape is not the missing liveness handshake.

2. QSEE/QSEEOS log-buffer registration
   - Patch: `out/aurel-latest-qsee-logbuf-oracle-2026-07-06.patch`
   - Image: `out/boot-joan-latest-qsee-logbuf.img`
   - Result: fastboot OK, no diagnostics, LineageOS returned at `t+52.2s`, post-reset `PS_HOLD`.
   - Conclusion: standalone QSEE log-buffer registration is not enough.

3. RPM `rpm_requests` reachability
   - Patch: `out/aurel-latest-rpm-rpmsg-reachability-oracle-2026-07-06.patch`
   - Image: `out/boot-joan-latest-rpm-rpmsg-oracle.img`
   - Result: fastboot OK, no diagnostics, LineageOS returned at `t+58.3s`, post-reset `PS_HOLD`.
   - Conclusion: RPM reachability alone is not enough; total absence of RPM channel setup is weaker as a root cause.

4. RPM BOB-mode default vote
   - Patch: `out/aurel-latest-rpm-bob-mode-oracle-2026-07-06.patch`
   - Image: `out/boot-joan-latest-rpm-bob-mode.img`
   - Result: fastboot OK, host monitor timed out at `t+108.4s`, later LineageOS returned, post-reset `PS_HOLD`.
   - Conclusion: bare `BOBB:1 bobm=2` vote is not enough. Timing perturbation may still make full RPM parity worth comparing.

5. DT-backed PM8998 L19 3.3 V always-on/default vote
   - Patch: `out/aurel-latest-rpm-l19-always-on-oracle-2026-07-06.patch`
   - Image: `out/boot-joan-latest-rpm-l19-always-on.img`
   - Result: fastboot OK, no diagnostics, LineageOS returned at `t+57.8s`, post-reset `PS_HOLD`.
   - Conclusion: single L19 vote is not enough.

6. Broader DT-backed PM/RPM overlay parity
   - Patch: `out/aurel-latest-rpm-pm-overlay-oracle-2026-07-06.patch`
   - Image: `out/boot-joan-latest-rpm-pm-overlay.img`
   - Result: fastboot OK, no diagnostics, LineageOS returned at `t+30.6s`, post-reset `PS_HOLD`.
   - Conclusion: standard DT L18+L19+BOB voltage/enable parity is not enough.

7. TCSR DLOAD/restart-cookie phandle
   - Patch: `out/aurel-latest-tcsr-dload-cookie-oracle-2026-07-06.patch`
   - Image: `out/boot-joan-latest-tcsr-dload-cookie.img`
   - Result: fastboot OK, no diagnostics, LineageOS returned at `t+55.5s`, post-reset `PS_HOLD`.
   - Conclusion: routing DLOAD-mode clearing through downstream-observed TCSR boot-misc cookie is not enough.

### PM8998 PON oracles

Both were rejected.

1. PM8998 PON S3 source/debounce
   - Patch: `out/aurel-latest-pon-s3-oracle-2026-07-06.patch`
   - Image: `out/boot-joan-latest-pon-s3-oracle.img`
   - Result: fastboot OK, no diagnostics, LineageOS returned at `t+30.5s`, post-reset `PS_HOLD`.
   - Conclusion: downstream `qcom,s3-debounce = <32>` and `qcom,s3-src = "kpdpwr-and-resin"` parity is not enough.

2. PM8998 PON reset-sequence/S1/S2 parity
   - Patch: `out/aurel-latest-pon-reset-seq-oracle-2026-07-06.patch`
   - Image: `out/boot-joan-latest-pon-reset-seq-oracle.img`
   - Result: fastboot OK, no diagnostics, LineageOS returned at `t+57.6s` host-script time, post-reset `PS_HOLD`.
   - Conclusion: fuller downstream PM8998 PON reset-sequence/S1/S2 parity is not enough.

Do not continue PMIC/PON unless a clearly different downstream state-changing delta appears.

### CPU/Kryo SCM errata comparison

No boot oracle was built.

Downstream has:

```text
android_kernel_lge_msm8998/drivers/soc/qcom/scm-errata.c
```

It can issue SCM BOOT command `0x12` for Kryo errata toggles:

- E74/E75 enable arg `0x1`
- E76 disable arg `0x100`

But:

- `CONFIG_QCOM_SCM_ERRATA` is optional debugfs/hotcpu support;
- it depends on `DEBUG_FS` and `QCOM_SCM`;
- it has no default enable in downstream Kconfig;
- checked joan defconfigs enable `CONFIG_QCOM_SCM=y` but not `CONFIG_QCOM_SCM_ERRATA`;
- init creates debugfs files and registers a `CPU_STARTING` notifier, but does not immediately apply to already-online boot CPUs.

Conclusion:

- Rejected at comparison time.
- Forcing SCM command `0x12` from mainline would be speculative, not direct downstream-default parity.
- Artifact: `out/aurel-kryo-scm-comparison-2026-07-06.txt`

## Current narrowed hypothesis

The blocker still looks like a secure/boot-chain/platform-state resetter, but not one solved by:

- `SEC_WDOG_DIS`;
- downstream runtime secure-watchdog sysfs disable;
- APSS WDT petting/reprogramming;
- panic timeout changes;
- single-core boot;
- cpuidle disable;
- high-memory no-map reservations;
- DLOAD-off SCM arg-shape parity;
- QSEE log-buffer registration;
- RPM `rpm_requests` reachability;
- bare BOB-mode RPM vote;
- single L19 default vote;
- standard DT L18+L19+BOB voltage/enable votes;
- TCSR DLOAD/restart-cookie phandle;
- PM8998 PON S3 source/debounce;
- PM8998 PON reset-sequence/S1/S2 parity;
- optional downstream Kryo SCM errata debugfs helper.

If the reset is a secure watchdog/liveness service that can only be satisfied from signed TZ/aboot firmware, it may be unfixable purely from mainline Linux. Do not promise a fix.

## Best next directions for Ember

Pick one, compare downstream vs mainline first, then build exactly one minimal oracle only if the downstream evidence shows an active default early boot-state delta.

Good candidate areas:

1. Fuller LGE panic/restart-reason + IMEM cookie handling distinct from rejected TCSR DLOAD phandle
   - Be careful not to repeat K018.
   - Look for writes/state changes not covered by the `qcom,dload-mode = <&tcsr_regs_2 0x13000>` oracle.

2. SMEM / bootreason / restart cookies
   - Determine whether downstream writes an early boot-state cookie mainline never writes.
   - Only test a concrete active path, not passive read-only reporting.

3. Another concrete QSEE/QSECOM state transition
   - Only if downstream evidence shows it runs before the reset window and mainline differs.
   - Do not repeat QSEE log-buffer registration or the TZ feature/version query mainline already does.

4. Full downstream RPM regulator/default-vote parity beyond the tested standard subset
   - The BOB-mode vote and standard DT voltage/enable bundle failed.
   - Only proceed if you find a different concrete RPM KVP / state transition that downstream sends early and mainline does not.

Avoid:

- another watchdog-only variant;
- another PMIC/PON S3 or reset-sequence variant;
- another standard regulator voltage/enable bundle;
- speculative Kryo command `0x12` SMC calls;
- repeating `fastboot getvar`.

## Suggested next workflow

1. Start from clean `joan/latest-clean-test`.
2. Compare downstream and mainline for exactly one candidate path.
3. If the downstream path is active by default and mainline lacks it, create one DEBUG-ONLY oracle patch.
4. Save patch under `lg-v30-port/out/` before booting.
5. Run:

```bash
git diff --check
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image.gz dtbs
cd /home/kumo02/vibe-coding-projects/coding/lg-v30-port
./make-testimage.sh /home/kumo02/vibe-coding-projects/coding/linux-mainline-v30
```

6. Copy image to a descriptive `out/boot-joan-latest-<oracle>.img`.
7. RAM-only boot with one fastboot client.
8. Classify as soon as either mainline diagnostics appear or LineageOS adb returns.
9. Read post-reset PON evidence if the phone returns.
10. Revert debug patch.
11. Rebuild clean and save a clean post-oracle image/hash.
12. Update:
    - `docs/kernel-change-ledger.md`
    - `docs/bringup-debug-state-2026-07-06.md`
    - `docs/2026-07-06_lg-v30-reset-cause-PS_HOLD.md`
    - `README.md` if top-level status changes
    - internal mirror handoffs
    - the internal tracker

## Tracking / public-readiness rules

Every kernel-impacting experiment must be recorded in `docs/kernel-change-ledger.md`, even rejected ones.

Each entry needs:

- exact handle: commit hash, branch, saved patch, image, transcript, or evidence artifact;
- class: `upstream-candidate`, `bringup-local`, `debug-only`, `rejected`, or `unknown`;
- touched files;
- downstream reference;
- purpose;
- real verification evidence;
- status;
- public/PR disposition: `ready`, `needs cleanup`, `blocked`, or `do not publish`.

Keep public-shaped branch work separate from debug-only experiments.

Current public-shaped baseline:

```text
joan/latest-clean-test
```

Avoid using `joan/latest-kernel` as the baseline unless specifically testing its debug perturbation.

## Artifact pointers

Recent Aurel artifacts live in:

```text
/home/kumo02/vibe-coding-projects/coding/lg-v30-port/out/
```

Most important latest artifacts:

```text
out/aurel-latest-pon-s3-oracle-2026-07-06.patch
out/aurel-pon-s3-fastboot-2026-07-06.txt
out/aurel-pon-s3-pon-2026-07-06.txt
out/aurel-latest-pon-reset-seq-oracle-2026-07-06.patch
out/aurel-pon-reset-seq-fastboot-2026-07-06.txt
out/aurel-pon-reset-seq-pon-2026-07-06.txt
out/aurel-kryo-scm-comparison-2026-07-06.txt
```

Latest clean rebuilt images after reverted debug oracles include:

```text
out/boot-joan-latest-clean-post-pon-s3-oracle.img
out/boot-joan-latest-clean-post-pon-reset-seq-oracle.img
```

See `docs/kernel-change-ledger.md` for full hashes and older artifacts.

## Copy/paste summary for Ember

Ember: please continue from `linux-mainline-v30` branch `joan/latest-clean-test`, not the debug breadcrumb branch. The current reset is still a controlled `PS_HOLD` return before mainline USB diagnostics. Do not retry SEC_WDOG_DIS, APSS watchdog petting, panic timeout, maxcpus/cpuidle, high-memory no-map, DLOAD arg-shape, QSEE log-buffer registration, RPM reachability, BOB-mode, L19/default regulator, standard L18+L19+BOB regulator overlay, TCSR DLOAD phandle, PM8998 PON S3 source/debounce, PM8998 PON reset-sequence/S1/S2, or optional Kryo SCM errata command-0x12. Those are recorded as rejected or comparison-only in the ledger.

Best next step: compare one concrete early downstream state-changing path that is active by default and still unmatched in mainline — likely fuller LGE/Qualcomm restart/boot-state/SMEM/IMEM cookie handling distinct from K018, or a different QSEE/QSECOM/RPM state transition with evidence that downstream runs it before the reset window. Build only one minimal oracle, RAM-only `fastboot boot`, then revert/rebuild clean and update the ledger/internal mirror/tracker.
