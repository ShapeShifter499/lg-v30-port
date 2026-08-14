# Card 94 continued: A540 runtime suspend unblocked, and why the SMMU cannot collapse

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-14

Continues `aurel-handoff-2026-08-13-to-next-session-lg-v30-gpu-connectivity.md`
and `ember-handoff-2026-08-13-to-aurel-card94-cx-gx.md`.

## 1. Aurel's perf-counter theory does not apply to joan

The leading hypothesis at handoff was a runtime-PM ownership race in
`msm_perfcntr.c`, with a fix built at `9826045a4` and never booted. It cannot
affect A540:

- `gpu->perfcntrs` is only allocated when `num_perfcntr_groups > 0`
  (`msm_gpu.c:1015`);
- that field is set only for a6xx/a7xx/a8xx (`a6xx_gpu.c:2681-2690`);
- there is no `a5xx_perfcntr_configure` at all.

So on joan `gpu->perfcntrs == NULL`, `msm_perfcntr_resume()` returns on its
first line, and `sel_work` is never queued. `9826045a4` is a real upstream bug
fix for a6xx and later and is worth submitting on its own merits, but booting
it here would have tested dead code.

## 2. The actual blocker was a port-local invention

`9f3d89120` ("drm/msm/adreno: gate A540 suspend on GDSC collapse", 2026-08-10,
MoA-authored) added a wait in `a5xx_pm_suspend()` for the GPMU to collapse the
SP/TP and RBCCU domains, failing the suspend on timeout. Mainline has no such
wait. The commit message justifies it with "can wedge MSM8998" -- speculative --
and describes itself as a test-only branch to be device-qualified.

It cannot succeed in the observed case:

- `a5xx_pm_resume()` powers RBCCU and then SP/TP up by hand on **every** resume;
- the GPMU that would later collapse them is loaded by `hw_init()`, which the
  driver defers to the first submit;
- a resume never followed by a submit therefore reaches autosuspend with both
  domains on and nothing running that could turn them off.

Aurel's own diagnostic trace is exactly that: resume at 56.487928 with
`needs_hw_init` set and the GPMU signature absent, autosuspend at 56.799740,
abort 524 usec later with `sp=00140000 rbccu=00140000` -- both bit-20s set,
precisely as `a5xx_pm_resume()` left them. A submit at 56.923930 runs
`hw_init()` and the following cycles collapse normally.

**Fix `ea1cdd7e2`**: skip the wait when `needs_hw_init` is still set. No GPMU
state to wait for, no work to drain, so it falls through to the mainline
sequence every other a5xx uses. `a6xx_gmu_shutdown()` (`a6xx_gmu.c:1421`)
special-cases its own microcontroller on the identical condition.

**Device-proven.** Boot `968306b4fd0e4da70c6596e462bb0d655820cecf4f98be6c1c0fe1860d659ed3`,
run `A540-HWINIT-GATE-20260814T085759Z`:

| | final-v4 | ea1cdd7e2 |
|---|---|---|
| `aborting suspend` | fired at 30.4 s | **0, never fired** |
| `runtime_status` | `error` | `active` |
| `runtime_suspended_time` | frozen at 27944 | 28270, advancing |

At `UPTIME=35.29`, `runtime_active_time` 5364 ms + `runtime_suspended_time`
28270 ms accounts for the whole life of the device. The GPU really was
suspended for 28.3 of its 35.3 seconds. `smmu_runtime_suspended_time` was
28743 over the same window, so the SMMU was collapsing and resuming too.

## 3. What the two boots then showed

Both boots reset silently later in the run. pstore captures
(`5f773503ac8779b6...`, `bbfec52484a66161...`, full 2 MiB via
`scripts/read-pstore-partition.sh`) contain the exact kernel release and end at
`[17.12]` / `[18.25]` with **no oops, panic, SError or fault** -- the same
signature-less secure-world reset as the original Card 94 fault.

A theory that the blanket `return 0` in `arm_smmu_runtime_resume()` left `sCR0`
with `CLIENTPD` set was **wrong and is withdrawn**: boot 1's own counters show
~28 s of successful collapse/resume cycles under exactly that code. `ab2b6869a`
(split the reset so the TLB invalidation and `sCR0` programming still run while
the stream-mapping and context-bank loops are skipped) closes a genuine gap --
neither the TLB nor `sCR0` is retained -- but it is not this bug, and boot 2
reset anyway.

What the two boots do establish:

- idle collapse/resume cycles work, repeatedly, for tens of seconds;
- the kill comes later, once greetd/phosh renders for real, consistent with the
  much older 213 s (greetd off) vs 17.1 s (greetd on) observation;
- so the failure is the **first translation after a collapse**, not the resume.

## 4. Downstream's model, and why residency is the remaining option

LG's `kgsl_smmu@5040000` (`msm-arm-smmu-8998.dtsi:145`) carries:

- `qcom,skip-init` -- and downstream's `arm_smmu_device_reset()` skips **only**
  the SMR/S2CR and context-bank loops under that option, still clearing sGFSR,
  issuing `TLBIALLH`/`TLBIALLNSNH` and programming `sCR0`. This matches the
  Card 94 register evidence exactly: sGFSR at GR0 0x48 read and wrote fine, the
  SMR window at 0x800 was fatal.
- `qcom,register-save`
- `vdd-supply = <&gdsc_gpu_cx>` -- independent confirmation that CX is the
  correct domain for the SMMU.

`qcom_scm_restore_sec_cfg()` was investigated and **rejected without a boot**:
downstream's `arm_smmu_restore_sec_cfg()` returns early unless the SMMU is
static-cb, and the kgsl SMMU is not. (K040, 2026-07-08, tested only the
MM-subsystem ids VIDEO/MDSS/MDSS_BOOT/ROT/VFE/CPP/JPEG against the July display
fault; `TZ_DEVICE_GPU` = 18 was never tried, but it is the wrong lever.)

So the mapping is not retained and cannot be reprogrammed. Downstream's own
alternative for that case is an extra power vote -- `arm_smmu_attach_dev()`
calls `arm_smmu_enable_regulators()` for any SMMU **without** `register-save`,
with the comment "We need an extra power vote if we can't retain register
settings across a power collapse".

**Candidate `521c2fe50`**: rename the feature bit to
`ARM_SMMU_FEAT_PIN_POWERED` (the old `RETAIN_ACROSS_PD` asserted retention,
now known false) and take a lifetime runtime-PM reference on the SMMU in
`arm_smmu_device_probe()`. This pins GPU_CX only; GPU_GX and VDD_GFX still
collapse, which is where the power is. Test J (SMMU pinned) previously survived
182 s.

## 5. Do-not-repeat

- The perf-counter race is inert on a5xx. Do not boot `9826045a4` for joan.
- The `sCR0`/`CLIENTPD` explanation of the boot-1 reset is withdrawn.
- `qcom_scm_restore_sec_cfg()` is not the lever for this SMMU (not static-cb).
- The SPTP/RBCCU gate is closed out: `ea1cdd7e2` is device-proven.
- pmOS sshd is not ready until roughly 40-60 s after `PMOS_USB_ENUMERATED`;
  earlier capture attempts fail with "scp: Connection closed" and that is not
  a device fault.

## 6. Boot 3 (`521c2fe50`, pinned SMMU): the reset becomes a diagnosable panic

Image `596ab8fe58768414ba2cba7416698407440be40b0d964efd38e4b504aaed0114`,
run `A540-SMMUPIN-20260814T100729Z`, pstore `pstore-after-reset.strings.txt`
in `out/audit-20260814/a540-smmupin-521c2fe50/`.

Pinning GPU_CX turned the silent secure-world reset into a **Linux panic with
a full backtrace** at 60.94 s:

```
SError Interrupt on CPU5, code 0x00000000bf000002
pc : qcom_smmu_tlb_sync+0xd8/0x104
Comm: phoc
  arm_smmu_iotlb_sync / iommu_unmap / msm_iommu_unmap
  msm_gem_vma_unmap / put_iova_spaces / msm_gem_close
  drm_gem_object_release_handle / drm_gem_handle_delete / drm_gem_close_ioctl
```

This is the same failure Aurel recorded for rejected image #1
(`bfd863403`): "asynchronous SError in `arm_smmu_unmap_pages()` while phoc
closed a GEM handle". It is **not** a property of that rejected approach; it is
what this SoC does once the GPU can actually reach runtime suspend, and it is
now reproducible and diagnosed.

## 7. Root cause of the SError: an unclaimed clock (Card 97 lane)

`msm8998.dtsi` gives the GPU node all three GFX BIMC gates --
`GCC_BIMC_GFX_CLK` ("mem"), `GCC_GPU_BIMC_GFX_CLK` ("mem_iface") and
`GCC_GPU_BIMC_GFX_SRC_CLK` ("mem_src") -- but gives `adreno_smmu` only the
first two. `mem_src` is the gate feeding the other two.

While the GPU could never suspend, its vote held the source on permanently and
the omission was invisible. Once the GPU suspends it drops that vote while the
SMMU is still live and still has to reach the GPU-side TBU to invalidate. The
branches remain enabled with no source behind them, the transaction gets no
response, and the external abort surfaces as an asynchronous SError -- reported
at `qcom_smmu_tlb_sync()` because its status read is what drains the posted
writes.

This is the same `GCC_GPU_BIMC_GFX_SRC_CLK` trap that broke A540 rendering in
July (killed by `clk_disable_unused` because nothing claimed it); the clock is
claimed now, but by only one of its two consumers.

Fix: `d63fa520b` (binding: allow a fourth "mem_src" clock) and `b9e50b685`
(claim it in `adreno_smmu`). Focused `dt_binding_check` on `arm,smmu.yaml`
exits 0; checkpatch --strict 0/0/0 on both.
