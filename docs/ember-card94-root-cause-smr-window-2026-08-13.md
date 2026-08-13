# Card 94 root cause — reading the Adreno SMMU's SMR window resets the SoC

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-13
State: ROOT CAUSE ISOLATED TO ONE REGISTER ACCESS; mechanism strongly indicated, not proven
Authorisation: Lance pre-authorised these RAM-only boots.

## Statement

Once the A540 has been initialised, **any access to the Adreno SMMU's stream-match
register window resets the SoC — including a plain read.** Mainline performs
exactly that access on every GPU runtime resume, because
`arm_smmu_runtime_resume()` unconditionally calls `arm_smmu_device_reset()`,
whose second phase walks `SMR(i)` / `S2CR(i)`.

That is Card 94.

## The isolating evidence

Markers were split so that every individual register access is separately
announced before it happens.

Boot time, before GPU init -- the same reads are harmless:

```text
[ 1.176388] JOAN-RST: P2a smr[0] about to READ SMR
[ 1.176493] JOAN-RST: P2b smr[0] SMR=0x00000000, about to READ S2CR
[ 1.176628] JOAN-RST: P2c smr[0] S2CR=0x000200ff sw{valid=0 id=0x0 cnt=0 type=2}
```

Resume, after GPU init -- the first read is fatal:

```text
[28.127857] JOAN-SMMU: calling device_reset
[28.127864] JOAN-RST: P1 clear sGFSR (smr_groups=3 cbs=3)
[28.128165] JOAN-RST: P2 sGFSR done, SMR loop next
[28.128173] JOAN-RST: P2a smr[0] about to READ SMR
<hard reset, nothing further ever printed>
```

`P2b` never appears. The kernel dies inside
`arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_SMR(0))`.

**It is not the GR0 region as a whole.** `sGFSR` lives at GR0 offset 0x48 and was
read *and written* successfully 300 us earlier in the same function. The SMR
window starts at GR0 offset 0x800. Only the latter is fatal.

**It is not the write.** An earlier run that skipped the writes but performed the
reads died in the same place, and the run before that -- which printed the index
without reading -- died on the write. Both accesses are fatal; the read is simply
the first one reached.

## Sequence of eliminations

Every step was a single-variable RAM-only boot.

| test | change | result |
|---|---|---|
| A | overclock corners removed (fast_rate 710 MHz) | reset -- overclock exonerated |
| B | single 257 MHz corner, mimicking `initial-pwrlevel=<4>` | reset -- entry corner exonerated |
| C/D | markers through the resume path | fault located to `arm_smmu_device_reset()` |
| E | `device_reset` skipped entirely | **survived 182 s, GPU resumed and rendered** |
| F | `device_reset` phase markers | narrowed to the SMR loop, index 0 |
| G | reads kept, writes skipped | still fatal -- so not write-only |
| H | SMR read and S2CR read separated | **fatal on the SMR(0) read** |

## Why boot works and resume does not

All three successful `device_reset` calls happen before the GPU firmware is
loaded:

```text
[ 1.1337] reset #1 -> P9 COMPLETE
[ 1.1690] reset #2 -> P9 COMPLETE
[ 1.6060] reset #3 -> P9 COMPLETE
[ 1.7259] a530_pm4.fw / a530_pfp.fw / a540_gpmu.fw2 loaded
[28.1281] reset #4 -> dies on SMR(0) read
```

`qcom_scm` and `qseecom` are both live on this device. The strongly indicated
mechanism is that bringing the GPU up hands its stream mapping to TrustZone --
the A540 uses a signed zap shader to leave secure mode -- after which the
non-secure world may no longer touch that window, and an attempt traps to the
secure side, which resets the SoC below Linux's visibility. That is consistent
with the complete absence of any oops, panic or fault message in every capture.

**This mechanism is indicated, not proven.** What is proven is the register, the
direction (read suffices), and the before/after-GPU-init boundary.

## Corroboration already in mainline

`drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c` carries:

```c
/*
 * MSM8998 LPASS SMMU reports 13 context banks, but accessing
 * the last context bank crashes the system.
 */
```

Same SoC, same failure class -- an SMMU register whose access hard-crashes
msm8998 -- already acknowledged upstream for a different instance.

## Consequences

- Card 94's title is wrong twice over. Suspend works; resume is the problem; and
  the problem is not in the GPU driver at all.
- The runtime-PM pin is a workaround that happens to prevent the GPU from ever
  needing a resume.
- This is very likely **not joan-specific**. Any msm8998 device that lets the
  Adreno GPU runtime-suspend will call `arm_smmu_device_reset()` on resume.
- joan's `adreno_smmu` is `compatible = "qcom,msm8998-smmu-v2", "qcom,smmu-v2"`
  and does **not** claim `"qcom,adreno-smmu"`, so it never selects the
  `adreno_impl` path in `arm-smmu-qcom.c`. Whether it should is the first
  question for a real fix.

## Shape of a fix, not yet attempted

Skipping the reset outright is not acceptable upstream. The plausible shapes are
a Qualcomm impl quirk that avoids re-initialising an already-configured GPU SMMU
after power collapse, or making the GPU SMMU claim the adreno impl so it can be
special-cased there. Downstream's `kgsl_smmu` node carries `qcom,retention`,
which says the block is expected to keep its state across collapse rather than be
re-reset -- and test E confirmed it does, since skipping the reset left the SMMU
translating correctly with no context faults.
