# A540 devfreq-cycle discriminator — 2026-08-10

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

The parent `6afe80c0e7a9ede8b4f11a02a530db9e616306f0` proved that A540 safely completes the GDSC gate and the existing VBIF halt/ACK/clear sequence when outer power remains on. This phase tested only the first operation inside `msm_gpu_pm_suspend()` with complete rollback:

1. retain the device-proven GDSC and VBIF sequences;
2. call `msm_devfreq_suspend()`;
3. immediately call `msm_devfreq_resume()`;
4. return `-EBUSY` before AXI, GPU-clock, or power-rail changes.

## Source and build

- branch: `joan/a540-devfreq-cycle-test`
- commit: `d0defdafd9f583ab63adf12100116a5d8ab0d53e`
- parent: `6afe80c0e7a9ede8b4f11a02a530db9e616306f0`
- build directory: `/data/buildcache/kbuild/build-a540-devfreq-cycle-d0defdafd`
- fresh directory used; no mixed incremental output packaged
- config SHA-256: `2ff4ee606a346b77c2d833c979eb08d18a52dde85c56f072153fff50c6561c36`
- `CONFIG_PM_DEBUG=y`, `CONFIG_PM_ADVANCED_DEBUG=y`
- battery/charger/RRADC/ADC5/ADC-TM5 built in
- full `Image.gz dtbs modules` build: exit 0 at `-j12`
- release: `7.2.0-rc2-gd0defdafd9f5`
- 1596 modules built
- uncompressed Image: 49,621,504 bytes (47.323 MiB; under 55.5 MiB ceiling)
- DT overlap scan: PASS, 108 ranges / 91 nodes / 12 benign aliases
- code-only checkpatch before commit: 0 errors, 0 warnings, 0 checks
- later full-email checkpatch: one commit-message line-length warning only; no code finding

## Packaging seal

- image: `out/boot-joan-a540-devfreq-cycle-d0defdafd.img`
- size: 27,815,936 bytes
- image SHA-256: `5a04133e643eb08414ef3d36045df7fb58942bcc754d8cf10015fb71c9400864`
- Image SHA-256: `3f56ebd035e75ac63fb0e8ba4fcbedc601bd1280d7c9fb213f1f90e3bb83e255`
- Image.gz SHA-256: `80701fae03317d3d99746f03fa1b9f53428f13e44a96c82a4b40690fe62ddd61`
- DTB SHA-256: `650913e7865f6dad78ba1cc48907c42d6de44695ab487325ff42cbb2db044e6a`
- ramdisk SHA-256: `43d1a861a694c40d5a51e9cfdf1db228d9e627b568f0d55a2f8404eda52d5b28`
- ramdisk/header/cmdline/UUID lineage matched the corrected battery-working baseline
- independently unpacked Image.gz, DTB, and Image matched fresh build outputs byte-for-byte

## Device result

One sealed RAM-only attempt through nym-nest; nothing flashed and no retry:

- LineageOS gate: PASS
- staged image hash: PASS
- fastboot transfer/boot: OK
- pmOS USB appeared after 12 seconds
- exact runtime kernel: `7.2.0-rc2-gd0defdafd9f5`

The callback logged:

```text
A540 GDSC gate passed: sp=00000001 rbccu=00000001
A540 devfreq cycle passed: ack=000f000f mask=0000000f
```

Runtime observations:

| checkpoint | runtime_status | runtime_usage | active_time | suspended_time | battery |
|---|---:|---:|---:|---:|---|
| immediate | active | 0 | 39,079 ms | 0 | 99%, 4.313 V, 32.0 C |
| ~2 min | active | 0 | 131,658 ms | 0 | 99%, 4.318 V, 32.0 C |
| >5 min | active | 0 | 313,506 ms | 0 | 99%, 4.317 V, 31.8 C |

At >5 minutes:

- GDSC-pass log count: 1
- devfreq-cycle log count: 1
- VBIF timeout count: 0
- ICC/RPM-SMD error count: 0
- bandwidth-removal error count: 0
- panic count: 0
- watchdog count: 0
- phone remained reachable and `qcom-battery` remained sane

## Conclusion

**SUCCESSFUL BOUNDARY DIAGNOSTIC, NOT A FIX.** `msm_devfreq_suspend()` followed by `msm_devfreq_resume()` is safe after the proven GDSC and VBIF sequence. The fatal boundary is now reduced to:

1. AXI/EBI clock disable;
2. GPU clock disable/rate changes;
3. outer regulator/rail disable.

This branch deliberately rejects runtime suspend and must not be promoted.

## Next one-variable peel

Test AXI/EBI with complete rollback:

1. GDSC and VBIF sequences;
2. devfreq suspend;
3. AXI/EBI disable;
4. AXI/EBI enable;
5. devfreq resume;
6. log success and return `-EBUSY` before GPU-clock or rail removal.

Every mutated stage must be restored because the runtime-PM error leaves the GPU active.

## Evidence

- `out/a540-devfreq-cycle-d0defdafd-package.log`
- `out/a540-devfreq-cycle-d0defdafd-ramboot.log`
- `out/a540-devfreq-cycle-d0defdafd-runtime-immediate.txt`
- `out/a540-devfreq-cycle-d0defdafd-runtime-checkpoints.txt`
