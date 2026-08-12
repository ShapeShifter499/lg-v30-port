# Card 94 — localised: `arm_smmu_device_reset()` on the Adreno SMMU

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-12
State: DEVICE RESULT; fault localised to a single function; no fix promoted
Authorisation: Lance pre-authorised further RAM-only boots before sleeping.

## Result

The Card 94 reset is not in the Adreno driver at all. It happens inside
`arm_smmu_device_reset()` when the **GPU SMMU** (`5040000.iommu`) runtime-resumes
after the GPU_GX power domain has been collapsed and restored.

Final markers, run RESUMETRACE3:

```text
[27.103930] JOAN-GDSC: gpu_gx enable enter
[27.103945] JOAN-GDSC: gpu_gx sw_reset pulsed
[27.103956] JOAN-GDSC: gpu_gx aon_reset pulsed
[27.103965] JOAN-GDSC: gpu_gx clamp released
[27.103989] JOAN-GDSC: gpu_gx toggle_on ret=0
[27.103999] JOAN-GDSC: gpu_gx force_mem_on done
[27.104013] JOAN-GDSC: gpu_gx enable RETURNING
[27.104025] JOAN-SMMU: runtime_resume enter (5040000.iommu)
[27.104049] JOAN-SMMU: clk_bulk_enable ret=0 (n=3)
[27.104058] JOAN-SMMU: calling device_reset
<hard reset, nothing further ever printed>
```

`JOAN-SMMU: device_reset returned` never appears, and `JOAN-ADRENO:
runtime_resume enter` never appears -- the GPU driver's own resume callback is
never reached. Both GDSCs power on successfully and return cleanly first, and
all three SMMU clocks enable with ret=0.

## How this was reached

Three device runs, each one variable, all RAM-only:

| test | change | outcome |
|---|---|---|
| A | overclock corners removed, fast_rate 710 MHz | reset at 18.565 s -- **overclock exonerated** |
| B | single 257 MHz corner, mimicking downstream `initial-pwrlevel = <4>` | reset at 16.865 s -- **entry corner exonerated** |
| C/D | pr_emerg markers through the resume path | **fault located** |

Test B's intervention was confirmed to have taken effect independently of the DT:
the boot logged `gfx-mem interconnect: 2056000 Bps` against `6800000 Bps` in the
850 MHz boot, and 2056000/6800000 is exactly 257/850.

## Why the SMMU is in the GPU's power domain at all

`msm8998.dtsi` deliberately attaches `adreno_smmu` to `GPU_GX_GDSC`, with a
comment explaining it as a workaround: GPU-GX's parent is GPU-CX, the SMMU needs
CX up, and the Adreno driver additionally has to manage the VDDMX RPM domain.

The consequence is that the GPU's runtime PM power-cycles the SMMU. Every time
the GPU suspends, the SMMU's hardware loses power; every time it resumes,
mainline's `arm_smmu_runtime_resume()` unconditionally calls
`arm_smmu_device_reset()` against it. At boot that same call is harmless -- it
runs at 1.7 s without incident. It is only fatal after a GX collapse.

## Candidate explanations, none yet tested

1. `arm_smmu_device_reset()` touches registers the GPU SMMU does not own after a
   power collapse -- on Qualcomm parts the GPU SMMU has secure/TZ-owned context
   banks, and an unauthorised write traps to the hypervisor, which would produce
   exactly this signature: instant reset, no kernel message, PS_HOLD class.
2. State retention: downstream's `kgsl_smmu` node carries `qcom,retention`,
   implying the block is expected to keep its state across collapse rather than
   be re-reset. Mainline resets unconditionally.
3. The SMMU is simply not ready that soon after the domain returns, and the
   global TLB sync inside the reset spins until a hardware watchdog fires.

## Next test

Gate `arm_smmu_device_reset()` behind a cmdline flag so both arms are the same
binary, and skip it on this SMMU. If the phone then survives a resume, the call
is confirmed as the killer -- and if the SMMU also still translates correctly,
retention is real and skipping the reset is a candidate *fix*, not merely a
diagnostic.

Note this is plausibly not joan-specific. Any msm8998 device that lets the GPU
runtime-suspend takes the same path.
