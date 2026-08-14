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

## 8. Boot 4 (`b9e50b685`, mem_src claimed): Card 94 criteria 1 and 2 PASS

Image `cf9b74a8fcc4a532dfc3131ce160572ced93d7d1e296745c3df90662e89182a3`,
run `A540-MEMSRC-20260814T104118Z`. Two captures, `device-immediate.txt` at
`UPTIME=64.40` and `device-after_idle.txt` at `UPTIME=338.47`.

Boot 3 panicked at 60.94 s. This one ran 5.6 minutes with phoc rendering
throughout:

| | at 64.40 s | at 338.47 s |
|---|---|---|
| `runtime_status` | suspended | suspended |
| `runtime_suspended_time` | 39381 | **310399** |
| `runtime_active_time` | 23342 | 26386 |
| `smmu_runtime_status` | active (pinned) | active (pinned) |

The GPU spent ~92% of the run suspended. Counts of `aborting suspend`,
`SPTP/RBCCU`, `context fault`, `GPU fault`, `hangcheck`, `recovery`,
`Internal error`, `SError` and `Kernel panic` were **all zero in both
captures**. `pm_genpd_summary` showed `gpu_gx off-0` with `gpu_cx on`,
exactly the intended split.

The SError is gone under real compositor rendering -- which is the same
workload that produced it in boot 3, via `drm_gem_close_ioctl`.

**Card 94 acceptance:**

1. suspends and resumes with no reset -- **PASS**
2. `runtime_status=suspended`, `runtime_suspended_time` advancing -- **PASS**
3. VDD_GFX releases when idle -- **PARTIAL**

On (3), PM8005 S1 went from `use=3 open=3 @644 mV` to `use=1 open=3
@628 mV`. The consumer breakdown is decisive:

```
s1                                  1    3      0    fast   628mV
   5000000.gpu-vdd                  0
   5000000.gpu-vdd                  1                       628mV
   5065000.clock-controller-vdd-gfx 0
```

`5065000.clock-controller-vdd-gfx` is the GX GDSC and it now correctly
releases -- that is the `2494f8beb`/`c0396bb9d` ownership work doing its job.
The remaining vote is the second of the two `vdd` consumers on the GPU node,
which are `msm_gpu.c:955` (`gpu->gpu_reg`, released by `disable_pwrrail()`,
the one showing 0) and `adreno_gpu.c:1119`
(`devm_pm_opp_set_regulators()`). The OPP core enables the supply on the
first `dev_pm_opp_set_rate()` and never lets go.

Fix `88dbc4e26`: call `dev_pm_opp_set_rate(dev, 0)` from
`adreno_runtime_suspend()` where a `vdd-supply` exists. `enable_clk()`
already calls `dev_pm_opp_set_rate(fast_rate)` on the way back up, which
restores both voltage and rate before the core clock is used, so the pairing
is symmetric and no OPP is ever run at the boot voltage.

## 9. Connectivity lanes are blocked on module deployment

A read-only enumeration on the live pmOS (`connectivity-probe.txt` in the
same run directory; no association, scan, pairing or TX) found:

- `lsmod` returns **nothing at all** -- no `ath10k_snoc`, `cfg80211`,
  `bluetooth`, `btqca`, `qrtr` or `ipa`;
- no `/sys/bus/qrtr/devices`, no `/sys/class/bluetooth`, netdevs are `lo` and
  `usb0` only;
- `remoteproc0` = `4080000.remoteproc`, state `offline`;
- `pd-mapper`, `tqftpserv`, `rmtfs` all absent; `ModemManager` and
  `wpa_supplicant` running with nothing to bind to.

The rootfs carries no module tree for these kernels -- the initramfs already
says `modprobe: FATAL: Module ext4 not found in directory
/lib/modules/7.2.0-rc2-g<hash>` on every boot. Each RAM-booted kernel has a
different release string, so `/lib/modules/<release>` never matches.

Wi-Fi, Bluetooth and cellular therefore cannot progress from a RAM boot
alone. They need the matching 1,596-module tree installed into the pmOS
rootfs on the SD card, which is a **persistent write to the SD card** and is
outside the RAM-only authorization. This needs Lance's explicit approval, and
the SD card has a prior fsck history (`docs/sd-card-fsck-and-recovery.md`).

The DT topology itself is already in place: `msm8998-lge-joan.dts` has the
`qcom,wcn3990-bt` node with all four supplies and the `&wifi` node with its
four supplies enabled.

## 10. Boot 5 (`88dbc4e26`): Card 94 CLOSED -- all three criteria PASS

Image `dbe4e7ab13f6bfdbbf91fee60e58840d50bbb7994fa7f1cb62e6e5541a84770e`,
run `A540-OPPVOTE-20260814T111613Z`.

```
kernel_exact=PASS              zero_aborting_suspend=PASS
cmdline_present=PASS           zero_sptp_rbccu=PASS
no_diag_marker=PASS            runtime_not_error=PASS
zero_gpu_fault=PASS            runtime_suspended_when_idle=PASS
zero_internal_error=PASS       suspend_counter_readable=PASS
zero_kernel_panic=PASS         suspend_counter_increased=PASS
zero_serror=PASS               vddgfx_readable=PASS
zero_context_fault=PASS        vddgfx_released=PASS
zero_unhandled_fault=PASS
zero_joan=PASS                 IDLE_GATE=PASS
```

`runtime_suspended_time` 39766 -> 313957 across the two captures,
`runtime_status=suspended` at both, `gpu_gx off-0` with `gpu_cx on`, and:

```
s1                                  0    3      0    fast   628mV
   5000000.gpu-vdd                  0
   5000000.gpu-vdd                  0
   5065000.clock-controller-vdd-gfx 0
```

**VDD_GFX use count is zero.** Every consumer has released the rail with the
GPU idle. This is the first time joan has done that: the board previously had
to pin it with `regulator-always-on` because nothing owned it.

### Final series on `joan/a540-suspend-hwinit-gate` (base final-v4 `76d180923`)

```
ea1cdd7e2 drm/msm/adreno: skip the A540 collapse gate when the GPU was never initialised
ab2b6869a iommu/arm-smmu: only skip the retained part of the reset on resume
521c2fe50 iommu/arm-smmu-qcom: keep the MSM8998 Adreno SMMU resident
d63fa520b dt-bindings: iommu: arm-smmu: allow the GFX bus source clock on MSM8998
b9e50b685 arm64: dts: qcom: msm8998: give the Adreno SMMU the GFX bus source clock
88dbc4e26 drm/msm/adreno: release the OPP core's supply vote on runtime suspend
```

All six: checkpatch --strict 0 errors / 0 warnings / 0 checks. Focused
`dt_binding_check` on `arm,smmu.yaml` exits 0. Builds exit 0, 0 errors, 1,596
modules, config SHA-256 `0bf3c437...` unchanged from final-v4 throughout.

Phone recovered to LineageOS after every boot, adbd returned to uid 2000, no
partition ever flashed.

### Still open

- `ab2b6869a` is retained on correctness grounds (the TLB and `sCR0` genuinely
  are not preserved across a collapse) but is not independently proven --
  `521c2fe50` pins the SMMU, so the resume path it corrects no longer runs on
  joan. It matters for any future attempt to let the SMMU collapse.
- Power saving from the VDD_GFX release is unquantified. `use=0` is proven;
  actual current draw is not measured.
- Whether GPU_CX could also be released with a different mechanism is untested.
  Residency is a deliberate trade, not a proof that collapse is impossible.
