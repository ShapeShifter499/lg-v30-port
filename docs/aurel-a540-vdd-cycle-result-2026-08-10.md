# A540 PM8005 S1 VDD-vote discriminator — 2026-08-10

Written-by: Aurel Nymvale (agent-aurel)
Date: 2026-08-10
State: DEVICE-PROVEN DIAGNOSTIC; not a fix; not promoted

## MOA provenance

- Harness/preset: `Hermes-Agent:moa/deep-flash`
- Aggregator/acting: `openai-codex:gpt-5.6-sol` (`reasoning=high`)
- Reference: `zai:glm-5.2` (`reasoning=high`)
- Reference: `minimax:MiniMax-M3` (`reasoning=high`)
- Reference: `deepseek:deepseek-v4-flash` (`reasoning=high`)

## Purpose and parent

The device-proven phase-6 parent `6c4503196f659e171ac422a2b6c9ed75ecf25e28`
proved that the complete driver-local sequence through devfreq suspension, AXI
removal, GPU clock/rate removal, and reverse-order restoration is safe when the
outer regulator vote is left in place.

This phase isolated the next call made by `msm_gpu_pm_suspend()`:
`regulator_disable(gpu->gpu_reg)`. Joan's live and source DT both describe one
real generic GPU supply:

```text
vdd-supply = <&pm8005_s1>;
```

There is no `vddcx-supply` property. The `gpu_cx` pointer nevertheless exists at
runtime because normal `devm_regulator_get(..., "vddcx")` substitutes a dummy
regulator for an absent supply.

The diagnostic retained all device-proven GDSC/VBIF/devfreq/AXI/clock stages,
removed the `gpu_reg` vote, sampled `regulator_is_enabled()`, restored the vote,
sampled it again, restored clocks/AXI/devfreq, and returned an error so the
runtime-PM core would not advance to genpd collapse.

A success marker required an observed physical transition of `off=0 on=1`.

## Attempt 1 — rejected before mutation

Source:

- branch: `joan/a540-vdd-cycle-test`
- commit: `fe9e852e79ab3c3c8aba954d1e690953f05a74a4`
- parent: `6c4503196f659e171ac422a2b6c9ed75ecf25e28`

Image:

- `out/boot-joan-a540-vdd-cycle-fe9e852e7.img`
- size: 27,815,936 bytes
- SHA-256: `2277a673a67cd027104010bd9e116ae7a32618bc96a37393ab9a347e4cc05087`
- release: `7.2.0-rc2-gfe9e852e79ab`
- battery-working ramdisk SHA-256: `43d1a861a694c40d5a51e9cfdf1db228d9e627b568f0d55a2f8404eda52d5b28`

One sealed RAM-only boot succeeded and reached pmOS USB. The helper logged:

```text
A540 VDD cycle failed: ret=-22 off=-1 on=-1
```

This was a safe no-mutation rejection: the original guard treated non-NULL
`gpu_cx` as evidence of a real second rail. Boot evidence proved the handle was
a regulator-core dummy:

```text
adreno 5000000.gpu: supply vddcx not found, using dummy regulator
```

The guard returned before devfreq, clocks, AXI, or either regulator was touched.
The phone remained reachable, battery stayed at 99%, and no ICC, panic,
watchdog, or timeout error appeared.

The rejected experiment remains in history; it was not amended away.

## Corrective source change

Commit `f8fe4956e5aa471e96483e3b9b899aaadb0bc43a` changed only the topology
oracle. It requires the real `vdd-supply` firmware property and rejects a real
`vddcx-supply` property on `gpu->pdev->dev`, rather than using regulator-handle
pointer presence.

Verification before the full build:

- `git diff --check`: PASS
- code-only `checkpatch.pl --strict`: 0 errors, 0 warnings, 0 checks
- focused `drivers/gpu/drm/msm/msm_gpu.o` build: PASS

## Attempt 2 — generic vote removed, physical rail retained

Build and seal:

- source: `f8fe4956e5aa471e96483e3b9b899aaadb0bc43a`
- parent: rejected experiment `fe9e852e79ab3c3c8aba954d1e690953f05a74a4`
- build directory: `/data/buildcache/kbuild/build-a540-vdd-cycle-f8fe4956e`
- config SHA-256: `2ff4ee606a346b77c2d833c979eb08d18a52dde85c56f072153fff50c6561c36`
- `CONFIG_PM_DEBUG=y`
- `CONFIG_PM_ADVANCED_DEBUG=y`
- fuel gauge, charger, RRADC, ADC5, and ADC-TM5 built in
- full `Image.gz dtbs modules` build: exit 0 at `-j12`
- release: `7.2.0-rc2-gf8fe4956e5aa`
- modules: 1,596
- Image: 49,687,040 bytes (47.385 MiB; below 55.5 MiB ceiling)
- DT overlap scan: PASS, 108 ranges / 91 nodes / 12 benign aliases

Image:

- `out/boot-joan-a540-vdd-cycle-f8fe4956e.img`
- size: 27,815,936 bytes
- SHA-256: `367a80dd32ad291d798e2ebed0d8ac84a0c40a28cfb596e60330710f0a069c14`
- Image SHA-256: `5e9fdd06e85c0a4a557ee1d5e8fa1dad682bde5084558b4f0658856a1f911ae1`
- Image.gz SHA-256: `5ac630e99521014e0b3620ce5d956ff8362378ea4b9df395acceb3c0f58845d7`
- DTB SHA-256: `650913e7865f6dad78ba1cc48907c42d6de44695ab487325ff42cbb2db044e6a`
- ramdisk SHA-256: `43d1a861a694c40d5a51e9cfdf1db228d9e627b568f0d55a2f8404eda52d5b28`
- unpacked Image.gz, DTB, and Image matched fresh build outputs byte-for-byte
- header, cmdline, offsets, UUIDs, and ramdisk matched the corrected
  battery-working baseline except the expected kernel-size field

One sealed RAM-only attempt was made through nym-nest; nothing was flashed and
there was no retry. pmOS USB appeared after 12 seconds, and the exact runtime
kernel was confirmed.

The helper repeatedly reported:

```text
A540 GDSC gate passed: sp=00000001 rbccu=00000001
A540 VDD cycle failed: ret=-11 off=1 on=1
```

Immediate runtime state:

```text
runtime_status=active
runtime_usage=0
runtime_suspended_time=0
battery=99%
qcom_icc_rpm_smd_send=0
Failed to remove bandwidth=0
Kernel panic=0
watchdog=0
```

The `-EAGAIN` result is intentional: the helper successfully removed and
restored its generic `gpu_reg` vote, but `regulator_is_enabled()` observed S1
still enabled both before and after restoration.

## Why PM8005 S1 stayed enabled

Two independent facts explain the result.

First, joan deliberately declares PM8005 S1 `regulator-always-on`:

```text
Kept always-on: with no consumer holding the rail at boot, the regulator
framework disables it during late cleanup, and the GPU_GX GDSC cannot power on
without VDD_GFX.
```

Second, the OPP framework independently acquires the same `vdd` supply to scale
voltage with GPU frequency. Live regulator debug state showed:

```text
s1 use_count=3 open_count=2
5000000.gpu-vdd  [generic msm_gpu consumer]
5000000.gpu-vdd  [OPP framework consumer, 1036 mV]
```

Therefore `disable_pwrrail()` removes only the generic driver's vote. It cannot
physically turn PM8005 S1 off in this configuration.

## Conclusion

**DEVICE-PROVEN BOUNDARY RESULT, NOT A FIX.** The generic
`disable_pwrrail()` operation was exercised with complete rollback and did not
physically collapse PM8005 S1. It is not the destructive hardware transition
that explains the full unpin candidate's reset.

This corrects the phase-6 shorthand that called the "outer rail" the sole
remaining untested boundary. The driver-local regulator vote is now tested.
The remaining physical power transition is the GPU GX/CX genpd collapse that
the PM core performs only after `a5xx_pm_suspend()` returns success.

Neither `fe9e852e7...` nor `f8fe4956e...` may be promoted. Both deliberately
return an error and keep runtime PM active.

## Implication for the original unpin plan

The clean SPTP/RBCCU-gated unpin candidate already exists as
`9f3d891201060dba13e0a28e641914365e9cf6cd` and was device-tested. It reached
userspace, then returned to LineageOS through the same `0x20` / PS_HOLD reset
class. The gate alone was therefore rejected as a complete fix.

All subsequent rollback diagnostics prove the driver callback through its
normal regulator-vote removal is stable when genpd collapse is prevented. The
next one-variable experiment must instrument or gate the GPU_GX/GPU_CX power
domain transition after the callback, not repeat the already-rejected clean
SPTP-only unpin and not enable the forbidden A540 VBIF software reset.

## Evidence

Attempt 1:

- `out/a540-vdd-cycle-fe9e852e7-package.log`
- `out/a540-vdd-cycle-fe9e852e7-ramboot.log`
- `out/a540-vdd-cycle-fe9e852e7-runtime-immediate.txt`
- `out/a540-vdd-cycle-fe9e852e7-topology-rejection.txt`

Attempt 2:

- `out/a540-vdd-cycle-f8fe4956e-package.log`
- `out/a540-vdd-cycle-f8fe4956e-ramboot.log`
- `out/a540-vdd-cycle-f8fe4956e-runtime-immediate.txt`
- `out/a540-vdd-cycle-f8fe4956e-regulator-state.txt`
