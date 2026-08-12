# Card 94 — CONFIRMED: `arm_smmu_device_reset()` is the killer

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-12
State: DEVICE-CONFIRMED by same-binary A/B; candidate fix identified; not promoted
Authorisation: Lance pre-authorised further RAM-only boots before sleeping.

## Confirmation

Gating `arm_smmu_device_reset()` behind `joan_smmu_skip_reset=`, so both arms are
the same binary, and skipping it for `5040000.iommu`:

| run | device_reset on GPU SMMU | outcome |
|---|---|---|
| RESUMETRACE3 | called | reset the instant it was called |
| SMMUSKIP | skipped | **survived 182 s, GPU resumed and rendered** |

Image `boot-joan-smmu-skipreset-ARMED.img`,
SHA-256 `b6f9421480c2ea3ed7500e1399d495974fb65b91b187561abe327bdbb7525143`.

## The resume genuinely happened

This is not a survival-by-not-doing-the-thing:

```text
[   26.392537] JOAN-SMMU: runtime_resume enter (5040000.iommu) skip=1
[   26.392557] JOAN-SMMU: clk_bulk_enable ret=0 (n=3)
[   26.392566] JOAN-SMMU: SKIPPING device_reset on 5040000.iommu
[   26.392960] JOAN-RESUME: 14 a5xx_pm_resume complete ret=0
```

`JOAN-ADRENO: runtime_resume enter` fired twice, and the GPU's own resume
completed with ret=0 at 26.39 s -- the same moment that killed the phone in every
previous run. Runtime PM recorded 24286 ms suspended before it, so the GPU really
had collapsed and really came back.

The GPU then worked: revision 540, `rbbm-status 0x1`, `last-fence 624` equal to
`retired-fence 624`, and phoc running.

## The SMMU still translated correctly

No context faults. The only `iommu` lines in dmesg are `cd00000.iommu` -- the
*display* SMMU -- printing normal probe information at 1.17 s.

That matters: if skipping the reset left the GPU SMMU unprogrammed, GPU submits
would fault immediately. They did not. **The block retains its state across the
GX power collapse**, which is consistent with downstream's `kgsl_smmu` node
carrying `qcom,retention`.

## One unrelated defect surfaced, and it fails safe

```text
[   26.790878] msm_dpu c901000.display-controller: aborting suspend:
              SPTP/RBCCU still on (sp=00140000 rbccu=00140000)
```

The *next* suspend refused to proceed, leaving `runtime_status=error`. That is
the known A540 SPTP/RBCCU predicate from Aurel's earlier gate work, it is not
this bug, and refusing to suspend is the safe direction.

## Why this is likely correct rather than lucky

Mainline already carries this exact failure class for this exact SoC, for a
different SMMU instance, in `arm-smmu-qcom.c`:

```c
/*
 * MSM8998 LPASS SMMU reports 13 context banks, but accessing
 * the last context bank crashes the system.
 */
```

An msm8998 SMMU where touching the wrong register hard-resets the SoC is a
documented upstream reality. The GPU SMMU after a power collapse looks like
another instance of it.

Also relevant: joan's `adreno_smmu` is `compatible = "qcom,msm8998-smmu-v2",
"qcom,smmu-v2"` and **not** `"qcom,adreno-smmu"`, so it never selects the
`adreno_impl` path in `arm-smmu-qcom.c`. Whether it should is an open question
worth answering before proposing anything upstream.

## Not claimed

- Skipping the reset unconditionally is **not** a fix. It is a confirmed
  diagnosis and a candidate direction.
- The mechanism is still unproven. Secure/TZ-owned context banks is the leading
  explanation but has not been demonstrated.
- Scope beyond joan is untested. Any msm8998 device that lets the GPU
  runtime-suspend takes this path, so this is plausibly not device-specific.

## Suggested next steps

1. Establish the mechanism: narrow which register write inside
   `arm_smmu_device_reset()` is fatal, by bisecting that function the same way
   the resume path was bisected.
2. Ask whether the GPU SMMU should be claiming the `qcom,adreno-smmu` compatible
   and the `adreno_impl` path.
3. Compare against downstream's `qcom,retention` handling for `kgsl_smmu`.
4. Only then decide the upstream-shaped fix -- most likely a Qualcomm impl quirk,
   not a change to generic `arm_smmu_runtime_resume()`.
