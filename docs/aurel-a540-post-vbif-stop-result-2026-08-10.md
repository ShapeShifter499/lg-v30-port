# A540 post-VBIF-stop discriminator — 2026-08-10

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

The device-proven parent `0b010f5deb59a7300888d3845390cf159ae48ae0`
returned `-EBUSY` immediately after the A540 GDSC gate and remained stable for
more than five minutes. That proved callback entry, the SP/TP and RBCCU bit-20
polls, status reads, and runtime-PM error rollback.

This phase moved the diagnostic stop point one stage later. It retained the
GDSC gate, then executed the existing A5xx VBIF sequence:

1. write mask `0x0f` to `A5XX_VBIF_XIN_HALT_CTRL0`;
2. wait for all four corresponding ACK bits in
   `A5XX_VBIF_XIN_HALT_CTRL1`;
3. read and log the ACK register;
4. clear `A5XX_VBIF_XIN_HALT_CTRL0`;
5. return `-EBUSY` for A540 before the software-reset decision and before
   `msm_gpu_pm_suspend()`.

The previously ignored ACK-wait return was also made fail-safe: a timeout is
logged and returned only after the halt request is cleared. The forbidden A540
software VBIF reset was not enabled.

## Source and build

- branch: `joan/a540-post-vbif-stop-test`
- commit: `6afe80c0e7a9ede8b4f11a02a530db9e616306f0`
- parent: `0b010f5deb59a7300888d3845390cf159ae48ae0`
- build directory: `/data/buildcache/kbuild/build-a540-post-vbif-6afe80c0e`
- fresh directory used; no mixed incremental output was packaged
- config SHA-256: `2ff4ee606a346b77c2d833c979eb08d18a52dde85c56f072153fff50c6561c36`
- `CONFIG_PM_DEBUG=y`
- `CONFIG_PM_ADVANCED_DEBUG=y`
- fuel gauge, charger, RRADC, ADC5, and ADC-TM5 built in
- full `Image.gz dtbs modules` build: exit 0 at `-j12`
- release: `7.2.0-rc2-g6afe80c0e7a9`
- 1596 modules built
- uncompressed Image: 49,687,040 bytes (47.385 MiB; under 55.5 MiB ceiling)
- DT overlap scan: PASS, 108 ranges / 91 nodes / 12 benign aliases
- code-only checkpatch before commit: 0 errors, 0 warnings, 0 checks

## Packaging seal

- image: `out/boot-joan-a540-post-vbif-6afe80c0e.img`
- size: 27,815,936 bytes
- image SHA-256: `f67e5eaf1b7e25ee4ce559b643a7b0b0691ddeefd010bcd2682f1e8f9b01efdb`
- Image SHA-256: `c07b5880a5a129206eb90256ee0d00deb7d21b423e5e3f413ad4130144bdecb5`
- Image.gz SHA-256: `1b5fcea5481069f464747439c0883a5408916a4a75f0bf903e8dfcabe8e38edf`
- DTB SHA-256: `650913e7865f6dad78ba1cc48907c42d6de44695ab487325ff42cbb2db044e6a`
- ramdisk SHA-256: `43d1a861a694c40d5a51e9cfdf1db228d9e627b568f0d55a2f8404eda52d5b28`
- ramdisk byte-identical to corrected battery baseline: PASS
- header version, offsets, page size, cmdline, boot UUID, and root UUID matched
  the corrected battery baseline
- unpacked Image.gz, appended DTB, and Image matched the fresh build outputs
  byte-for-byte

## Device result

One sealed RAM-only attempt through nym-nest; nothing flashed and no retry:

- LineageOS identity gate: PASS
- staged image hash: PASS
- fastboot transfer: 27,164 KiB, OK
- fastboot boot: OK
- pmOS USB appeared after 12 seconds
- exact runtime kernel: `7.2.0-rc2-g6afe80c0e7a9`

The callback logged:

```text
A540 GDSC gate passed: sp=00000001 rbccu=00000001
A540 post-VBIF stop: ack=000f000f mask=0000000f
```

Bit 20 is clear in both GDSC status registers. The low and high copies of all
four VBIF ACK bits are set in `0x000f000f`; the requested low mask was `0x0f`.
The ACK wait did not time out.

Runtime observations:

| checkpoint | runtime_status | runtime_usage | active_time | suspended_time | battery |
|---|---:|---:|---:|---:|---|
| immediate | active | 0 | 38,431 ms | 0 | 99%, 4.318 V, 32.0 C |
| ~2 min | active | 0 | 132,174 ms | 0 | 99%, 4.320 V, 32.0 C |
| ~3 min | active | 0 | 193,635 ms | 0 | 99%, 4.320 V, 32.0 C |
| >5 min | active | 0 | 348,677 ms | 0 | 99%, 4.319 V, 31.8 C |

At the >5-minute checkpoint:

- `runtime_enabled=enabled`
- `control=auto`
- `runtime_active_kids=0`
- GDSC-pass log count: 1
- post-VBIF log count: 1
- VBIF timeout count: 0
- SPTP/RBCCU timeout count: 0
- `qcom_icc_rpm_smd_send` count: 0
- `Failed to remove bandwidth` count: 0
- panic count: 0
- watchdog count: 0
- phone remained reachable over USB networking
- `qcom-battery` remained registered and sane

## Conclusion

**SUCCESSFUL BOUNDARY DIAGNOSTIC, NOT A FIX.** The existing A540 VBIF
halt/ACK/clear sequence is safe when outer power remains on. The fatal boundary
is now inside `msm_gpu_pm_suspend()`:

1. `msm_devfreq_suspend()`;
2. disable AXI/EBI clock;
3. disable GPU clocks and lower rates;
4. disable the outer power rail/regulator.

The branch deliberately rejects runtime suspend and must not be promoted.

## Next one-variable peel

Exercise only the first outer-power operation with complete rollback:

1. retain the GDSC and VBIF sequences;
2. call `msm_devfreq_suspend()`;
3. disable AXI/EBI;
4. immediately re-enable AXI/EBI;
5. call `msm_devfreq_resume()`;
6. log success and return `-EBUSY` before GPU-clock or rail removal.

Do not simply disable AXI and return: the runtime-PM core will leave the device
active after the error, so every stage tested before `-EBUSY` must be restored.
If this cycle is stable, move the next boundary to GPU clock disable/enable.

## Evidence

- `out/a540-post-vbif-6afe80c0e-package.log`
- `out/a540-post-vbif-6afe80c0e-ramboot.log`
- `out/a540-post-vbif-6afe80c0e-runtime-immediate.txt`
- `out/a540-post-vbif-6afe80c0e-runtime-checkpoints.txt`
- `out/a540-post-vbif-6afe80c0e-runtime-gt5min.txt`
