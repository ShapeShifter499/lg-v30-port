# A540 complete GPU-clock-cycle discriminator — 2026-08-10

Written-by: Aurel Nymvale (agent-aurel)
Date: 2026-08-10
State: DEVICE-PROVEN DIAGNOSTIC; not a fix; not promoted

## MOA provenance

- Harness/preset: `Hermes-Agent:moa/deep-flash`
- Aggregator/acting: `openai-codex:gpt-5.6-sol` (`reasoning=high`)
- Reference: `zai:glm-5.2` (`reasoning=high`)
- Reference: `minimax:MiniMax-M3` (`reasoning=high`)
- Reference: `deepseek:deepseek-v4-flash` (`reasoning=high`)

## Purpose

Parent `6e8a6df9e6487fec51b8f19f90d7a4750ea775e7` proved that the A540 GDSC gate, VBIF halt/ACK/clear, devfreq suspend/resume, and AXI/EBI disable/enable stages are safe. This phase added exactly the complete generic GPU-clock stage and restored every changed layer in reverse order:

1. retain the device-proven A540 GDSC and VBIF sequences;
2. suspend devfreq;
3. disable AXI/EBI;
4. run `disable_clk()`:
   - bulk-disable/unprepare the GPU clock group;
   - request 27 MHz on the core clock;
   - request 0 Hz on the RBBM timer;
5. run `enable_clk()`:
   - restore the GPU fast rate;
   - restore the 19.2 MHz RBBM timer;
   - bulk-prepare/enable the GPU clock group;
6. re-enable AXI/EBI;
7. resume devfreq;
8. return `-EBUSY` before `disable_pwrrail()`.

The helper performs best-effort reverse-order rollback even if clock restoration reports an error, resumes devfreq, and returns the first clock/AXI restoration error.

## Source and build

- source checkout: `/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30-a540-sptp-gate`
- branch: `joan/a540-clock-cycle-test`
- commit: `6c4503196f659e171ac422a2b6c9ed75ecf25e28`
- parent: `6e8a6df9e6487fec51b8f19f90d7a4750ea775e7`
- source worktree: clean
- build directory: `/data/buildcache/kbuild/build-a540-clock-cycle-6c4503196`
- fresh output directory; no mixed output packaged
- config SHA-256: `2ff4ee606a346b77c2d833c979eb08d18a52dde85c56f072153fff50c6561c36`
- `CONFIG_PM_DEBUG=y`
- `CONFIG_PM_ADVANCED_DEBUG=y`
- battery/fuel-gauge/charger/ADC dependencies built in
- full `Image.gz dtbs modules` build: exit 0 at `-j12`
- release: `7.2.0-rc2-g6c4503196f65`
- 1,596 modules built
- uncompressed Image: 49,687,040 bytes (47.385 MiB; under the 55.5 MiB ceiling)
- DT overlap scan: PASS, 108 ranges / 91 nodes / 12 benign aliases
- code-only checkpatch before commit: 0 errors, 0 warnings, 0 checks
- full-email checkpatch after commit: one commit-description line-length warning only; code remained 0/0/0

## Packaging seal

- image: `out/boot-joan-a540-clock-cycle-6c4503196.img`
- size: 27,815,936 bytes
- image SHA-256: `d1c4c750a11c5edbee1d63a855667e7c3dc9f8f89c54ab5965ad206ce1ae321b`
- combined Image.gz+DTB SHA-256: `4d0fbdad6294e5c1494b636a583c40464890e4e0c6427863f0e61f9c89a7757a`
- Image SHA-256: `1556ab8f1c722934adeb3677b88eb42579955897910454ccd40d227904d7279f`
- Image.gz SHA-256: `2c7e61c828373348a0af8d288a7634fefdce24a52870a773df9a643204d0ac0f`
- DTB SHA-256: `650913e7865f6dad78ba1cc48907c42d6de44695ab487325ff42cbb2db044e6a`
- ramdisk SHA-256: `43d1a861a694c40d5a51e9cfdf1db228d9e627b568f0d55a2f8404eda52d5b28`
- independently unpacked Image.gz, DTB, and Image matched fresh build outputs byte-for-byte
- ramdisk and every boot-header field matched the corrected battery-working baseline except the expected candidate kernel payload size
- cmdline retained the proven pmOS boot/root UUIDs and `panic=5 ignore_loglevel`

## Device result

One sealed RAM-only attempt through nym-nest; nothing flashed and no retry:

- LineageOS identity gate: PASS (`4.4.302-LineageOS+`, `sys.boot_completed=1`)
- local and nym-nest staged hashes: identical
- fastboot transfer/boot: OK
- pmOS USB appeared after 13 seconds
- exact runtime kernel: `7.2.0-rc2-g6c4503196f65`

The callback logged exactly once:

```text
A540 GDSC gate passed: sp=00000001 rbccu=00000001
A540 clock cycle passed: ack=000f000f mask=0000000f
```

Runtime observations:

| checkpoint | runtime_status | runtime_usage | active_time | suspended_time | battery |
|---|---:|---:|---:|---:|---|
| immediate | active | 0 | 33,295 ms | 0 | 99%, 4.315 V, 33.5 C |
| ~2 min | active | 0 | 116,268 ms | 0 | 99%, 4.314 V, 33.5 C |
| >5 min | active | 0 | 298,036 ms | 0 | 99%, 4.313 V, 33.3 C |

At >5 minutes:

- GDSC-pass marker count: 1
- complete clock-cycle marker count: 1
- VBIF timeout count: 0
- ICC/RPM-SMD error count: 0
- bandwidth-removal error count: 0
- panic count: 0
- watchdog count: 0
- generic timeout count: 0
- phone remained reachable and the battery subsystem remained sane

## Conclusion

**SUCCESSFUL BOUNDARY DIAGNOSTIC, NOT A FIX.** The complete `disable_clk()` followed by `enable_clk()` stage is safe on this device when the outer GPU rails remain enabled. Together with the preceding device-proven phases, every operation before `disable_pwrrail()` in `msm_gpu_pm_suspend()` has now been exercised with rollback and survived beyond five minutes.

This does **not yet prove** that rail disable is the root cause. It narrows the sole untested generic suspend operation to:

```c
if (gpu->gpu_cx)
    regulator_disable(gpu->gpu_cx);
if (gpu->gpu_reg)
    regulator_disable(gpu->gpu_reg);
```

The diagnostic deliberately rejects runtime suspend and must not be promoted.

## Next one-variable peel

Test the outer rail with complete rollback while preserving all proven stages:

1. GDSC and VBIF sequences;
2. devfreq suspend;
3. AXI disable;
4. GPU clocks/rates down;
5. outer rails off;
6. outer rails on;
7. GPU clocks/rates restored;
8. AXI enabled;
9. devfreq resumed;
10. log success and return `-EBUSY`.

Because `disable_pwrrail()` currently discards regulator errors and because `enable_pwrrail()` can partially enable `gpu_reg` before failing on `gpu_cx`, the rail-cycle diagnostic should record individual rail presence/return codes and perform explicit best-effort rollback. If the rail cycle resets the device, split `gpu_cx` and `gpu_reg` into separate one-variable tests rather than combining more changes.

## Evidence

- `out/a540-clock-cycle-6c4503196-package.log`
- `out/a540-clock-cycle-6c4503196-ramboot.log`
- `out/a540-clock-cycle-6c4503196-runtime-immediate.txt`
- `out/a540-clock-cycle-6c4503196-runtime-checkpoints.txt`
