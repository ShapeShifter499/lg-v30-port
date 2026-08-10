# A540 SPTP/RBCCU gate result — 2026-08-10

Written-by: Aurel Nymvale (agent-aurel)
Date: 2026-08-10
State: REJECTED AS FIX; retained as device evidence; not promoted

## MOA provenance

- Harness/preset: `Hermes-Agent:moa/deep-flash`
- Aggregator/acting: `openai-codex:gpt-5.6-sol` (`reasoning=high`)
- Reference: `zai:glm-5.2` (`reasoning=high`)
- Reference: `minimax:MiniMax-M3` (`reasoning=high`)
- Reference: `deepseek:deepseek-v4-flash` (`reasoning=high`)

## Required baseline was proven first

The earlier `boot-joan-master.img` did not contain the fuel-gauge driver, so it
was not accepted as the parent baseline.

The corrected Ember/master battery image was RAM-booted with no source change:

- image: `out/boot-joan-master-batt.img`
- size: `27811840` bytes
- SHA-256: `c4d727542ad8e0082ffb242d88256274fb7df4c478eff95f1cf1836a5b666b6d`
- kernel: `7.2.0-rc2-g47041183b55e`
- source: `47041183b55e1389ab6f595c06c63a09422dc747`
- archived config: `docs/master-47041183b.config`
- archived config SHA-256: `0bf3c4370e774528470558b1b4675ff2bcaafb6212e02d67c9118e40f0689651`
- runtime battery: `qcom-battery`, 99%, 4328124 uV, 308 deci-C on first capture
- later liveness capture: 99%, 4321278 uV, 303 deci-C
- zero fuel-gauge, ICC, or GPU errors in the baseline runtime capture

This is the corrected newer continuation of Ember's earlier device-proven
`9bfc50add...` all-subsystems state. Battery source did not change between the
two; the earlier master failure was a build-config omission.

## Hypothesis tested

Downstream KGSL only treats A540 as idle after both GPMU domains report powered
off:

- `A5XX_GPMU_SP_PWR_CLK_STATUS` bit 20 clear
- `A5XX_GPMU_RBCCU_PWR_CLK_STATUS` bit 20 clear

Mainline proceeded from VBIF halt directly to `msm_gpu_pm_suspend()`, which
disables AXI, clocks, and the outer rail. The test hypothesis was that mainline
cut outer power before those inner GDSCs finished collapsing.

The candidate:

1. removed the temporary A540 runtime-PM reference;
2. for A540 only, polled both status bits clear for the downstream-equivalent
   bounded 100-usec window before touching VBIF;
3. returned `-ETIMEDOUT` with both registers logged if either remained on;
4. restored the performance-counter stream when runtime suspend aborted;
5. deliberately did **not** add an A540 VBIF software reset, because both
   upstream and downstream restrict that reset to variants where it is safe;
6. did not include the rejected ICC vote-drop experiment.

## Candidate provenance and build

- branch: `joan/a540-sptp-gate-test`
- commit: `9f3d891201060dba13e0a28e641914365e9cf6cd`
- parent: `47041183b55e1389ab6f595c06c63a09422dc747`
- build directory: `/data/buildcache/kbuild/build-a540-sptp-gate-47041183b`
- config SHA-256: `2ff4ee606a346b77c2d833c979eb08d18a52dde85c56f072153fff50c6561c36`
- `CONFIG_PM_DEBUG=y`
- `CONFIG_PM_ADVANCED_DEBUG=y`
- fuel gauge, charger, RRADC, ADC5, and ADC-TM5 all built in
- full `Image.gz dtbs modules` build: exit 0 at `-j12`
- focused A540 objects: PASS
- `git diff --check`: PASS
- `checkpatch.pl --strict`: 0 errors, 0 warnings, 0 checks
- 1596 modules built for release `7.2.0-rc2-g9f3d89120106`
- uncompressed Image: 49687040 bytes (47.385 MiB; under 55.5 MiB ceiling)
- DT overlap scan: PASS, 108 ranges / 91 nodes / 12 benign aliases

## Packaging seal

Candidate image:

- `out/boot-joan-a540-sptp-gate-9f3d89120.img`
- size: `27815936` bytes
- SHA-256: `83aa2cb8b1a80f477fe7a12151b2eca85dcf2e32659c5ee9edc22e588ba5d08f`
- embedded release: `7.2.0-rc2-g9f3d89120106`
- uncompressed Image SHA-256: `c6a425f0a3220600ee2002c57e66f78a89643c6f8fece27d3579082340a78606`
- Image.gz SHA-256: `3a0af41b1eccc5b8a761ae3e8ddf23e4ba08ea4599f509cd0fbe9cf8583b3355`
- DTB SHA-256: `650913e7865f6dad78ba1cc48907c42d6de44695ab487325ff42cbb2db044e6a`
- ramdisk SHA-256: `43d1a861a694c40d5a51e9cfdf1db228d9e627b568f0d55a2f8404eda52d5b28`
- ramdisk byte-identical to corrected battery baseline: PASS
- header version/offsets/page size/cmdline byte-equivalent: PASS
- boot UUID: `a5d40a96-ddec-44ac-bc37-b5519a9da397`
- root UUID: `9a5df9d1-ee25-47b6-9b3a-a2602b939bd0`
- unpacked Image.gz, DTB tail, and Image matched build outputs byte-for-byte

## Device result

One sealed RAM-only attempt via nym-nest; nothing flashed, no retry:

- LineageOS identity gate: PASS
- image hash on nym-nest: PASS
- fastboot transfer: 27164 KiB, OK
- fastboot boot: OK
- pmOS USB `18d1:d001`: appeared after 12 seconds
- before SSH/runtime collection succeeded, phone returned to LineageOS
- returned LineageOS kernel: `4.4.302-LineageOS+`
- returned boot reason: `ro.boot.bootreason=bootloader`
- `ro.boot.product.lge.bootreasoncode=0x20`
- `ro.boot.product.lge.hiddenreset=0`
- PMIC SID0 power-off reason: PS_HOLD
- PMIC SID2 power-off reason: GP1 / Keypad_Reset1

Raw pstore was pulled immediately, read-only:

- binary SHA-256: `bc92ea636f0c0eeacb1e8f25f1579525ec32ac765dbce9adaa0115cffc5ab12e`
- strings SHA-256: `0165d3ae360da97a39a2be19b1ab23193243ffadcc86b7841525a419d096a6a8`
- candidate banner at time 0: confirmed
- switch-root: 10.634754 s
- udev start: 12.683604 s
- rootfs remount: 17.617579 s
- boot filesystem mounted: 17.924173 s
- console record corrupts/truncates immediately after that point
- raw bytes contain no `aborting suspend`, `SPTP/RBCCU`, `rbccu=`,
  `rpm-smd`, `-110`, kernel panic, watchdog, or orderly restart marker

Evidence files:

- `out/a540-sptp-gate-9f3d89120-manifest.prebuild.txt`
- `out/a540-sptp-gate-9f3d89120-package.log`
- `out/a540-sptp-gate-9f3d89120-ramboot.log`
- `out/a540-sptp-gate-9f3d89120-pstore.bin`
- `out/a540-sptp-gate-9f3d89120-pstore.strings.txt`
- `out/a540-sptp-gate-9f3d89120-pstore.meta.txt`
- `out/a540-sptp-gate-9f3d89120-los-reset-classification.txt`

## Conclusion

**REJECTED AS A FIX.** The GDSC-off readiness gate alone does not make A540
runtime collapse safe. It did not emit its timeout path in the coherent pstore
window, and the failure depth/reset class matches the clean unpin-only family:
userspace/rootfs comes up, then the device exits through the same generic
`0x20`/PS_HOLD path.

The result narrows the failure to the sequence after (or concurrent with) the
successful GDSC status check. It does not justify forcing the forbidden A540
VBIF software reset.

## Next one-variable discriminator

Use the same battery-working parent and the same GDSC gate, but after a
successful gate:

1. log the SP and RBCCU status values once;
2. deliberately return `-EBUSY` **before** VBIF halt and before
   `msm_gpu_pm_suspend()`;
3. keep the error-path perf-counter rollback;
4. retain `PM_ADVANCED_DEBUG` and read `runtime_status`, `runtime_usage`,
   `runtime_active_time`, and `runtime_suspended_time` from the stable phone.

If that survives, callback entry/GPMU collapse/error rollback are proven and
the fatal region is bounded to VBIF halt or subsequent AXI/clock/rail removal.
Then peel those stages one at a time. Do not promote either diagnostic branch.
