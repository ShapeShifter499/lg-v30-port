# A540 AXI/EBI-cycle discriminator — 2026-08-10

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

The parent `d0defdafd9f583ab63adf12100116a5d8ab0d53e` proved that the GDSC gate, VBIF halt/ACK/clear, and devfreq suspend/resume cycle are safe. This phase tested the next operation inside `msm_gpu_pm_suspend()` with complete reverse-order rollback:

1. retain the device-proven GDSC and VBIF sequences;
2. suspend devfreq;
3. disable the AXI/EBI clock;
4. re-enable the AXI/EBI clock;
5. resume devfreq;
6. return `-EBUSY` before GPU-clock or outer-rail changes.

The rollback helper propagates an AXI re-enable failure instead of claiming success.

## Source and build

- branch: `joan/a540-axi-cycle-test`
- commit: `6e8a6df9e6487fec51b8f19f90d7a4750ea775e7`
- parent: `d0defdafd9f583ab63adf12100116a5d8ab0d53e`
- build directory: `/data/buildcache/kbuild/build-a540-axi-cycle-6e8a6df9e`
- fresh directory used; no mixed output packaged
- config SHA-256: `2ff4ee606a346b77c2d833c979eb08d18a52dde85c56f072153fff50c6561c36`
- PM debug/advanced debug and battery dependencies built in
- full `Image.gz dtbs modules` build: exit 0 at `-j12`
- release: `7.2.0-rc2-g6e8a6df9e648`
- 1596 modules built
- uncompressed Image: 49,687,040 bytes (47.385 MiB; under 55.5 MiB ceiling)
- DT overlap scan: PASS, 108 ranges / 91 nodes / 12 benign aliases
- code-only checkpatch before commit: 0 errors, 0 warnings, 0 checks

## Packaging seal

- image: `out/boot-joan-a540-axi-cycle-6e8a6df9e.img`
- size: 27,815,936 bytes
- image SHA-256: `f87edebb83e201be5374b39f422aad54ae58f14d9eda49d6260c0eb35924d880`
- Image SHA-256: `29ff1939046cd37af0aa978a4b075a00b0c2bdff7f225d0b30e29fc774835a3b`
- Image.gz SHA-256: `e032fb51523f0425f151bab8209da1c5acc823b26d131f8dd718cbacc60a939e`
- DTB SHA-256: `650913e7865f6dad78ba1cc48907c42d6de44695ab487325ff42cbb2db044e6a`
- ramdisk SHA-256: `43d1a861a694c40d5a51e9cfdf1db228d9e627b568f0d55a2f8404eda52d5b28`
- ramdisk/header/cmdline/UUID lineage matched the corrected battery-working baseline
- independently unpacked Image.gz, DTB, and Image matched fresh build outputs byte-for-byte

## Device result

One sealed RAM-only attempt through nym-nest; nothing flashed and no retry:

- LineageOS gate and staged hash: PASS
- fastboot transfer/boot: OK
- pmOS USB appeared after 12 seconds
- exact runtime kernel: `7.2.0-rc2-g6e8a6df9e648`

The callback logged:

```text
A540 GDSC gate passed: sp=00000001 rbccu=00000001
A540 AXI cycle passed: ack=000f000f mask=0000000f
```

Runtime observations:

| checkpoint | runtime_status | runtime_usage | active_time | suspended_time | battery |
|---|---:|---:|---:|---:|---|
| immediate | active | 0 | 38,656 ms | 0 | 99%, 4.314 V, 32.8 C |
| ~2 min | active | 0 | 126,079 ms | 0 | 99%, 4.316 V, 32.8 C |
| >5 min | active | 0 | 307,139 ms | 0 | 99%, 4.316 V, 32.5 C |

At >5 minutes:

- GDSC-pass log count: 1
- AXI-cycle log count: 1
- VBIF timeout count: 0
- ICC/RPM-SMD error count: 0
- bandwidth-removal error count: 0
- panic count: 0
- watchdog count: 0
- phone remained reachable and battery remained sane

## Conclusion

**SUCCESSFUL BOUNDARY DIAGNOSTIC, NOT A FIX.** AXI/EBI disable followed by re-enable is safe when the GPU clocks and outer rail remain on. The remaining fatal boundary is reduced to:

1. `disable_clk()` — bulk GPU-clock disable plus core/rbbm rate changes;
2. `disable_pwrrail()` — outer regulators/rail disable.

This branch deliberately rejects runtime suspend and must not be promoted.

## Next one-variable peel

Test the complete GPU-clock stage with reverse-order rollback:

1. GDSC and VBIF sequences;
2. devfreq suspend;
3. AXI disable;
4. GPU-clock disable/rate lowering;
5. GPU-clock enable/rate restoration;
6. AXI enable;
7. devfreq resume;
8. log success and return `-EBUSY` before rail disable.

If stable, the outer rail is isolated as the failing stage. If it resets, split bulk clock gating from core/rbbm rate changes in follow-up images.

## Evidence

- `out/a540-axi-cycle-6e8a6df9e-package.log`
- `out/a540-axi-cycle-6e8a6df9e-ramboot.log`
- `out/a540-axi-cycle-6e8a6df9e-runtime-immediate.txt`
- `out/a540-axi-cycle-6e8a6df9e-runtime-checkpoints.txt`
