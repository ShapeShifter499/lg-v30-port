# Card 94 — XPU2 is the mechanism, and a working workaround

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-13
State: MECHANISM IDENTIFIED FROM FIRMWARE; WORKAROUND DEVICE-VALIDATED; not upstream-shaped
Authorisation: Lance pre-authorised these RAM-only boots.

## Mechanism: XPU2

The TrustZone image was dumped from the device's `tz` partition
(2 MiB, sha256 `fd756df523ca9b47f55c00805c8e897474cb6eaab1bcd4faba9beda2c5f63010`,
kept local at `~/joan-images/tz/tz.img` on nym-nest and **deliberately not
committed** -- it is signed LG/Qualcomm firmware).

It is a plain AArch64 ELF: 14 LOAD segments, entry `0x14680000`, Shannon entropy
**4.95 bits/byte**, so signed but neither encrypted nor packed, and therefore
readable.

It contains a protected-region table of 32-byte records:

| # | region | size |
|---|---|---|
| 4 | `0x05020000-0x05040000` | 128 KiB |
| **5** | **`0x05040000-0x05060000`** | **128 KiB -- the Adreno SMMU register window** |
| 6 | `0x05100000-0x05160000` | 384 KiB |
| 7 | `0x05800000-0x06000000` | 8 MiB |

and the firmware's own format string names the mechanism and the record layout:

```text
xpu: Prt: %d: Start: 0x%x, End: 0x%x, Perm0: 0x%x, Perm1: 0x%x,
     SecR: 0x%x, NSecR: 0x%x, NSecW: 0x%x, NSecW: 0x%x, Cfg: 0x%x
```

**`NSecR` and `NSecW` are separate permissions.** Non-secure *read* is
independently denied, which is exactly why a bare read of `SMR(0)` is fatal
while every other part of `arm_smmu_device_reset()` is fine.

Violations route through `HAL_XPU2_ERROR_F_CLIENT_PORT` /
`HAL_XPU2_ERROR_F_CONFIG_PORT` into the firmware's NoC error path
(`NOC_ERROR`, `NoC Error ISR`, `/dev/NOCError`), which resets the SoC **from the
secure world**. That is why no capture in this entire investigation contains an
oops, panic or fault: Linux is never told.

The GPU's own register base `0x05000000` is **absent** from the table, matching
the observed behaviour exactly -- GPU registers are hammered constantly without
incident, and only SMMU register access kills the SoC.

### Still not proven

Why the *boot-time* resets succeed. The region is evidently armed during GPU
bring-up rather than unconditionally. The table proves ownership and the timing
evidence proves when it engages, but the arming trigger has not been located in
the firmware.

## Workaround: never let the SMMU be power-cycled

Since the block retains state across collapse -- proved earlier by skipping the
reset entirely and finding the SMMU still translating with zero context faults --
the fix is to stop it being power-cycled, not to make re-initialisation survive.

Two parts:

1. `adreno_smmu` moved from `GPU_GX_GDSC` to `GPU_CX_GDSC`, matching both
   neighbouring SoCs (msm8996 uses `mmcc GPU_GDSC`, sdm845 uses
   `gpucc GPU_CX_GDSC`; msm8998 was the only one sharing GX with the GPU).
2. The SMMU pinned runtime-active, so CX stays up.

Part 1 alone was tested and is **not sufficient** -- `GPU_CX_GDSC` is votable and
collapses once idle, so the SMMU was still power-cycled. Both parts are needed.

Crucially the GPU's own GX domain is still free to collapse, so GPU power
management is preserved rather than disabled.

## Device result

Image `boot-joan-smmu-pinned.img`,
SHA-256 `d28c19f0fbe658fe11ce2f1f16abafce2dcbf4303db656aeb8b1fd2feab7043e`.

```text
[28.261453] JOAN-GDSC: gpu_gx enable enter
[28.261503] JOAN-GDSC: gpu_gx sw_reset pulsed
[28.261515] JOAN-GDSC: gpu_gx aon_reset pulsed
[28.261524] JOAN-GDSC: gpu_gx clamp released
[28.261549] JOAN-GDSC: gpu_gx toggle_on ret=0
[28.262014] JOAN-RESUME: 14 a5xx_pm_resume complete ret=0
```

| check | result |
|---|---|
| GX collapsed and returned | yes, 2 collapse events, full sequence |
| GPU genuinely suspended | `runtime_suspended_time = 26172` ms |
| GPU SMMU re-reset | **no** -- both `device_reset` calls were `cd00000.iommu` (display) |
| GPU resumed | `a5xx_pm_resume ret=0` at the moment that previously reset the phone |
| GPU rendering | rev 540, `rbbm-status 0x1`, last-fence 756 == retired-fence 756, phoc up |
| IOMMU context faults | 0 |
| uptime | 182 s |

## What this is not

- **Not upstream-shaped.** The pin is keyed on `dev_name()` and must become a
  Qualcomm impl property or a DT-expressed capability instead.
- **Power cost unmeasured.** Holding GPU_CX up has some cost; GX, the expensive
  domain, still collapses, but the CX cost has not been quantified.
- **Does not fix the A540 SPTP/RBCCU suspend predicate**, which still leaves
  `runtime_status=error` after a later suspend attempt. That fails safe and is a
  separate defect.
- **Scope beyond joan untested**, though any msm8998 device that lets the Adreno
  GPU runtime-suspend takes this path.
