# A540 pre-VBIF-stop discriminator — 2026-08-10

Written-by: Aurel Nymvale (agent-aurel)
Date: 2026-08-10
State: DEVICE-PROVEN DIAGNOSTIC; not a fix; not promoted

## MOA provenance

- Harness/preset: `Hermes-Agent:moa/deep-flash`
- Aggregator/acting: `openai-codex:gpt-5.6-sol` (`reasoning=high`)
- Reference: `zai:glm-5.2` (`reasoning=high`)
- Reference: `minimax:MiniMax-M3` (`reasoning=high`)
- Reference: `deepseek:deepseek-v4-flash` (`reasoning=high`)

## Parent and purpose

The preceding A540 GDSC-gate candidate, commit `9f3d891201060dba13e0a28e641914365e9cf6cd`, proved that merely waiting for GPMU SP/TP and RBCCU bit 20 to clear did not make the full suspend sequence safe. It reached userspace and then returned to LineageOS through the generic `0x20` / PS_HOLD path without a gate timeout or RPM-SMD `-110`.

This phase moved the diagnostic stop point to immediately after a successful GDSC check. For A540 it:

1. polls `A5XX_GPMU_SP_PWR_CLK_STATUS` bit 20 clear;
2. polls `A5XX_GPMU_RBCCU_PWR_CLK_STATUS` bit 20 clear;
3. reads and logs both registers once;
4. returns `-EBUSY` before VBIF halt and before AXI, clock, or outer-rail removal;
5. relies on the parent error-path fix to restore performance counters.

This intentionally prevents runtime suspension. Its purpose is to prove whether callback entry, GPMU polling/status reads, and runtime-PM error rollback are safe.

## Source and build

- branch: `joan/a540-pre-vbif-stop-test`
- commit: `0b010f5deb59a7300888d3845390cf159ae48ae0`
- parent: `9f3d891201060dba13e0a28e641914365e9cf6cd`
- build directory: `/data/buildcache/kbuild/build-a540-pre-vbif-0b010f5de`
- fresh directory used; the mixed incremental parent directory was not used for packaging
- config SHA-256: `2ff4ee606a346b77c2d833c979eb08d18a52dde85c56f072153fff50c6561c36`
- `CONFIG_PM_DEBUG=y`
- `CONFIG_PM_ADVANCED_DEBUG=y`
- fuel gauge, charger, RRADC, ADC5, and ADC-TM5 all built in
- full `Image.gz dtbs modules` build: exit 0 at `-j12`
- release: `7.2.0-rc2-g0b010f5deb59`
- 1596 modules built
- uncompressed Image: 49,621,504 bytes (47.323 MiB; below 55.5 MiB ceiling)
- DT overlap scan: PASS, 108 ranges / 91 nodes / 12 benign aliases
- source diff check: PASS
- code-only checkpatch before commit: 0 errors, 0 warnings, 0 checks
- later full-email checkpatch: one commit-message line-length warning only; no code finding; the already-built/tested commit was not rewritten

## Packaging seal

- image: `out/boot-joan-a540-pre-vbif-0b010f5de.img`
- size: 27,815,936 bytes
- image SHA-256: `b7555b4cfecb62d7fe5071f0cd28cae58be8f5d1ab17d6875a1830ca6800420a`
- Image SHA-256: `177b79a9fd6b07f36af8fcf0faecfc1d3217f755dcfb594b94166befe98d8e14`
- Image.gz SHA-256: `abd2f260d39f18bb115bc59391d45626bace9e264e262180bde597334a0a4a0c`
- DTB SHA-256: `650913e7865f6dad78ba1cc48907c42d6de44695ab487325ff42cbb2db044e6a`
- ramdisk SHA-256: `43d1a861a694c40d5a51e9cfdf1db228d9e627b568f0d55a2f8404eda52d5b28`
- ramdisk byte-identical to the corrected battery-working baseline: PASS
- header version, offsets, page size, cmdline, boot UUID, and root UUID matched the baseline
- unpacked Image.gz, appended DTB, and uncompressed Image matched the fresh build outputs byte-for-byte
- boot UUID: `a5d40a96-ddec-44ac-bc37-b5519a9da397`
- root UUID: `9a5df9d1-ee25-47b6-9b3a-a2602b939bd0`

## Device result

One sealed RAM-only attempt through nym-nest; nothing flashed and no retry:

- LineageOS gate: PASS
- staged image hash: PASS
- fastboot transfer: 27,164 KiB, OK
- fastboot boot: OK
- pmOS USB appeared after 12 seconds
- exact runtime kernel: `7.2.0-rc2-g0b010f5deb59`

The first runtime callback logged:

```text
A540 pre-VBIF stop: sp=00000001 rbccu=00000001
```

Bit 20 is clear in both values, directly proving that both downstream-derived power-off predicates passed. Low bit 0 remains set and was not part of the downstream predicate.

Runtime observations:

| checkpoint | runtime_status | runtime_usage | active_time | suspended_time | battery |
|---|---:|---:|---:|---:|---|
| immediate | active | 1 | 36,977 ms | 0 | 99%, 4.314 V, 29.3 C |
| ~2 min | active | 0 | 121,234 ms | 0 | 99%, 4.324 V, 29.8 C |
| ~3 min | active | 0 | 182,607 ms | 0 | 99%, 4.324 V, 29.8 C |
| >5 min | active | 0 | 350,592 ms | 0 | 99%, 4.324 V, 30.0 C |

At the >5-minute checkpoint:

- `runtime_enabled=enabled`
- `control=auto`
- `runtime_active_kids=0`
- pre-VBIF log count: 1 (`dev_info_once`)
- SPTP/RBCCU timeout count: 0
- `qcom_icc_rpm_smd_send` count: 0
- `Failed to remove bandwidth` count: 0
- panic count: 0
- watchdog count: 0
- phone remained reachable over USB networking
- `qcom-battery` remained registered and sane

The rootfs clock showed 1969 because the known RTC issue remains; uptime is the valid duration source.

## Conclusion

**SUCCESSFUL BOUNDARY DIAGNOSTIC, NOT A FIX.** Callback entry, both GDSC polls, both register reads, returning `-EBUSY`, and performance-counter rollback are safe. Runtime PM correctly reaches usage count zero, but remains active because the diagnostic rejects suspend. This keeps the battery-working system stable.

The fatal region is therefore after the successful GDSC check: either the A540 VBIF halt/ack/clear sequence or `msm_gpu_pm_suspend()` and its AXI/clock/outer-rail removal.

This branch must not be promoted. It deliberately prevents GPU runtime suspension.

## Next one-variable peel

From this exact branch and config:

1. retain the GDSC gate and status log;
2. execute only the existing VBIF halt request, wait for ACK, then clear halt;
3. log the ACK register;
4. return `-EBUSY` before `msm_gpu_pm_suspend()`;
5. RAM-boot once and repeat the same runtime/battery/error checkpoints.

If stable, VBIF halt/ack/clear is safe and the fatal boundary moves into AXI/clock/rail removal. If it resets, VBIF halt itself is the failing stage. Do not add the forbidden A540 VBIF software reset.

## Evidence

- `out/a540-pre-vbif-0b010f5de-package.log`
- `out/a540-pre-vbif-0b010f5de-ramboot.log`
- `out/a540-pre-vbif-0b010f5de-runtime-immediate.txt`
- `out/a540-pre-vbif-0b010f5de-runtime-checkpoints.txt`
- `out/a540-pre-vbif-0b010f5de-runtime-final.txt`
- `out/a540-pre-vbif-0b010f5de-runtime-gt5min.txt`
