# Ember handoff — LG V30 (`joan`) latest-kernel mainline bringup

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

## TL;DR

The LG V30 latest-kernel bringup is still blocked by an early reset before
mainline USB diagnostics appear.

The safest current baseline is:

- Kernel repo: `/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30`
- Branch: `joan/latest-clean-test`
- Base: `origin/master` `8cdeaa50e` (`Linux 7.2-rc2`)
- State: clean, four clean DTS commits ahead of upstream
- Harness/docs repo: `/home/kumo02/vibe-coding-projects/coding/lg-v30-port`
- Harness state: clean, latest commit `d0cd717 docs: record latest joan discriminator tests`

The latest clean baseline image boots through the fastboot protocol, but mainline
still never exposes the mass-storage/debug channel; LineageOS returns afterward.

Use the latest docs first:

- `docs/kernel-change-ledger.md`
- `docs/bringup-debug-state-2026-07-06.md`
- `docs/public-upstreaming-plan.md`
- this file: `docs/ember-handoff-2026-07-06.md`

## Safety rules

These are binding unless Lance explicitly changes them:

- Do not flash.
- Do not write phone storage.
- Use RAM-only `fastboot boot`.
- Lance must be physically present for device work.
- Enter fastboot via `adb reboot bootloader`.
- Use exactly one fastboot client at a time.
- Avoid `fastboot getvar`; it previously wedged LG aboot.
- If the monitor sees LineageOS adb return, classify immediately and stop waiting.
- Keep test images under:
  `/home/kumo02/vibe-coding-projects/coding/lg-v30-port/out/`
- Report any package installs. Aurel installed none in this batch.

Fastboot script precheck note:

- Prefer `pgrep -a -x fastboot` to detect existing fastboot clients.
- A `ps | grep [f]astboot` check inside a heredoc command can false-positive on
  the parent shell command text.

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

This branch intentionally excludes the debug-only breadcrumb commit from
`joan/latest-kernel` because that branch changes timing and is not public/PR-ready.

## Latest clean baseline result

Image:

```text
/home/kumo02/vibe-coding-projects/coding/lg-v30-port/out/boot-joan-latest-clean.img
```

SHA-256:

```text
47418aebd86c929b59cd09d243d93abe7ab03d85310d11015dfcd530474d47c1
```

Size:

```text
15736832 bytes
```

Fastboot result:

```text
Sending 'boot.img' ... OKAY
Booting ... OKAY
Finished. Total time: about 5.525s
```

Host classifier:

```text
No mainline mass-storage/debug channel appeared.
LineageOS adb returned at t+46.7s after boot handoff.
```

Conclusion:

Latest upstream v7.2-rc2 plus the clean joan DTS stack still does not fix the
reset.

## What Aurel already tested and rejected

### 1. Secure watchdog / SCM disable path

Aurel tried downstream-inspired `SEC_WDOG_DIS` approaches:

- mainline `qcom_scm_probe()` call
- early raw SMC
- exact downstream function ID `0x02000107`
- mainline/SMCCC function ID `0x42000107`
- enable arg `0` and `1`
- multi-convention raw SMC spray

Result:

- None survived to mainline USB diagnostics.
- The multi-convention spray shortened the host-side return window to about
  `~30s`, so treat it as noisy/harmful, not a fix.
- On running LineageOS, downstream's own sysfs secure-watchdog disable path also
  failed with:

```text
scm_call failed: func id 0x42000107, ret: -2
Failed to deactivate secure wdog
```

Conclusion:

`SEC_WDOG_DIS` is not a known-good survival path on this device/TZ firmware.

### 2. Panic / APSS watchdog / SCM timing

Aurel tested:

- `panic=30`
- disabling the APSS watchdog DT node
- PSCI reset oracle at `qcom_scm_probe()` entry
- downstream-style APSS WDT bark/bite/pet loop
- APSS WDT `EN=3` / wakeup-enable style behavior

Results:

- `panic=30`: no useful shift; LineageOS returned around `~46.5s`.
- APSS watchdog DT node disabled: no useful shift; LineageOS returned around
  `~46.6s`.
- PSCI reset oracle at `qcom_scm_probe()` returned around `~29.7s`, proving SCM
  probe is reached early enough to run before the normal reset window.
- Downstream-style APSS WDT petting did not fix the reset.

Conclusion:

The reset does not look like ordinary Linux panic, simple mainline qcom_wdt
misprogramming, missing APSS WDT petting, or SCM being called too late.

### 3. Latest new-path discriminators

Aurel then tested three newer hypotheses on `joan/latest-clean-test`.

#### Single-core / secondary CPU discriminator

Image:

```text
out/boot-joan-latest-maxcpus1.img
```

Cmdline:

```text
maxcpus=1
```

SHA-256:

```text
5bd01b0a987563027abbb968810b1b796201cbffb32e99effa4fc95d672c93e8
```

Result:

```text
fastboot boot protocol OKAY, total 5.522s
no mainline USB/diag
LineageOS adb returned at t+29.5s
```

Interpretation:

The reset is not simply caused by secondary CPU bringup or missing secondary-CPU
errata handling.

#### CPU idle / PSCI idle discriminator

Image:

```text
out/boot-joan-latest-cpuidleoff.img
```

Cmdline:

```text
cpuidle.off=1 nohlt
```

SHA-256:

```text
3f4b26656dc1af381128aa211787297ce85808e638287a1c21f7c550b5f9955d
```

Result:

```text
fastboot boot protocol OKAY, total 5.520s
no mainline USB/diag
LineageOS adb returned at t+45.8s
```

Interpretation:

Generic mainline CPU idle / PSCI idle is unlikely to be the primary trigger.

#### Downstream high-memory reservation / allocator-XPU discriminator

Saved debug patch:

```text
/home/kumo02/vibe-coding-projects/coding/lg-v30-port/out/aurel-latest-highmem-reserve-test-2026-07-06.patch
```

WebDAV copy:

```text
Talk/Shared_AI_agents_files/patches/aurel-latest-highmem-reserve-test-2026-07-06.patch
```

Image:

```text
out/boot-joan-latest-highmem-reserve.img
```

SHA-256:

```text
c9f4545b790084dd82b139109dc29dffa516f1c3a17620a003db3b6241a886a6
```

What it tested:

The patch reserved downstream-observed high memory pools as `no-map`, including
`qseecom`, `secure_region`, `sp_region`, `adsp_region`, and a CMA-like high
region, to test whether mainline was tripping a firmware/XPU reset by allocating
memory LG/TZ expects to own.

Result:

```text
git diff --check passed
build succeeded
fastboot boot protocol OKAY, total 5.516s
no mainline USB/diag
LineageOS adb returned at t+29.4s
```

Interpretation:

The reset is unlikely to be caused only by mainline allocating those high physical
ranges before the diag gadget appears.

Cleanup:

The high-memory debug patch was saved and uploaded, then reverted. The kernel
tree was rebuilt clean afterward.

## Current narrowed conclusion

The reset still looks like a secure / boot-chain / platform-state resetter.

It is not solved by:

- latest upstream alone
- `SEC_WDOG_DIS`
- downstream sysfs secure-watchdog disable
- APSS WDT disable/pet/reprogramming
- panic timeout changes
- single-core boot
- generic cpuidle disable
- simply reserving downstream high-memory secure/shared pools

## Best next path

Investigate downstream early IMEM / restart / memory-dump setup as a single clean
oracle.

Strong candidate areas:

- downstream `drivers/soc/qcom/memory_dump_v2.c`
  - downstream dmesg shows `MSM Memory Dump base table set up` at `0.115s`
- LGE panic / restart reason code, especially:
  - `drivers/soc/qcom/lge/lge_handle_panic.c`
- IMEM / SMEM boot cookies
- restart reason / bootreason setup
- early memory dump table pointer written into IMEM

Suggested next oracle:

1. Start from clean `joan/latest-clean-test`.
2. Add one debug-only latest-clean patch that mimics only the early downstream
   memory-dump / IMEM setup enough to see whether reset timing changes.
3. Build with:

```bash
git diff --check
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j6 Image.gz dtbs
cd /home/kumo02/vibe-coding-projects/coding/lg-v30-port
./make-testimage.sh /home/kumo02/vibe-coding-projects/coding/linux-mainline-v30
```

4. Copy the image to a descriptive name under `out/`.
5. RAM-only boot it with one fastboot client.
6. Classify as soon as mainline diag appears or LineageOS adb returns.
7. Save the patch under `out/`, revert kernel tree, rebuild clean.
8. Update:
   - `docs/kernel-change-ledger.md`
   - `docs/bringup-debug-state-2026-07-06.md`
   - `README.md` if the top-level status changed
   - WebDAV handoffs
   - Deck card #43

Do not bundle this oracle with watchdog, cpuidle, or CPU changes.

## Tracking / public-readiness rules

Every kernel-impacting experiment must be recorded in:

```text
docs/kernel-change-ledger.md
```

Even rejected experiments need:

- commit hash or saved patch path
- touched files
- purpose
- real verification evidence
- status
- public/PR disposition

Status classes:

- `upstream-candidate`
- `bringup-local`
- `debug-only`
- `rejected`
- `unknown`

Public/PR disposition:

- `ready`
- `needs cleanup`
- `blocked`
- `do not publish`

Keep public-shaped branch work separate from debug-only experiments.

Current public-shaped baseline:

```text
joan/latest-clean-test
```

Avoid using `joan/latest-kernel` as the baseline unless specifically testing its
debug perturbation; it includes breadcrumb instrumentation and changed timing.

## Commit attribution convention

Use Lance's required trailers for commits/handoffs:

```text
Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:<actual Ember model>
```

Do not use `Co-Authored-By`.

For Aurel/Hermes docs already written, the corresponding trailer is:

```text
Assisted-by: Hermes:gpt-5.5
```

## Final state from Aurel

- Phone: back in LineageOS, adb-visible as `LGUS9986e606d55`
- Fastboot: no device, no client running
- Kernel repo: clean on `joan/latest-clean-test`
- Harness repo: clean on `master` before this handoff file was added
- Latest saved findings commit before this handoff file:
  `d0cd717 docs: record latest joan discriminator tests`
- No packages installed
- No flashing
- No phone-storage writes
