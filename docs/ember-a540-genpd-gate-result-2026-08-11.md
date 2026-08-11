# Card 94 — A540 late genpd gate, device result 2026-08-11

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-11
For: Aurel Nymvale (agent-aurel), Lance
State: DEVICE RESULT BANKED; gate validated; **target boundary NOT exercised**; no fix promoted

## Verdict in one line

The gate works and is proven to have fired, the Phase 8 precondition failure is
fixed, and the boot got substantially further — but the **late runtime-PM GX/CX
collapse this diagnostic was built to test never occurred**, so this is
*inconclusive* for Aurel's hypothesis rather than evidence against it.

## What was built

- source: `93cc2be54` on `joan/a540-genpd-gate-test`, branched from the clean
  gated unpin `9f3d891201060dba13e0a28e641914365e9cf6cd` (NOT from Phase 8)
- hook: `gdsc_disable()` in `drivers/clk/qcom/gdsc.c`, which `gdsc_register()`
  installs as `generic_pm_domain.power_off` (verified in-tree at `gdsc.c:507`)
- scope: both `gpu_gx` and `gpu_cx`. Gating GX alone is unsound — `gpu_gx.parent
  = gpu_cx.pd`, so a child reporting off makes the parent eligible to collapse,
  leaving GX physically on under a collapsed parent.
- toggle: `joan_gpu_gate=1` armed / `joan_gpu_gate=0` control, so **both arms are
  the same binary** and no build difference can confound the comparison.

Images (kernel and ramdisk byte-identical between arms; only cmdline differs):

```text
Image.gz            19995336 bytes  sha256 58577c013fabeaae8601c446ea3f5a78...
joan DTB               69066 bytes  sha256 650913e7865f6dad78ba1cc48907c42d...
kernel+dtb appended            sha256 9be5071e57e83566b2ac220c8ec2caf7037e45c1...
ramdisk (donor, device-proven) sha256 43d1a861a694c40d5a51e9cfdf1db228d9e627b5...
gate1 image         30535680 bytes  sha256 41d6ad8ee60b1d148e0af74164f5628b...
gate0 image         30535680 bytes  sha256 4338ddb7c3be63f352f48632d15875c3...
pstore capture       2097152 bytes  sha256 e7efa41d97a1d7955d988e576f5ad755...
```

Ramdisk and cmdline were taken from the Phase 8 image so only the kernel and the
one added parameter vary. RAM-only `fastboot boot`; nothing flashed.

## Validity instrumentation — this is why the result is trustworthy

The marker is emitted for GPU domains **in both arms, before the gate is
consulted**, precisely because a gate that never fires is indistinguishable from
a gate that worked. Captured from pstore:

```text
[    0.000000] JOAN-GPU-GATE: armed=1
[    1.352302] JOAN-GPU-GATE: gdsc_disable(gpu_gx) hit=1 gate=1
[    1.352430] JOAN-GPU-GATE: gdsc_disable(gpu_cx) hit=2 gate=1
[    2.276013] JOAN-GPU-GATE: gdsc_disable(gpu_gx) hit=3 gate=1
[    2.276073] JOAN-GPU-GATE: gdsc_disable(gpu_cx) hit=4 gate=1
kernel 7.2.0-rc2-g93cc2be5482c
```

Parameter parsed, gate armed, gate fired four times, correct kernel. Not a false
pass.

## Phase 8's precondition failure is fixed

Unlike `a856f868e`, the GPU stack bound completely:

```text
[ 1.792839] adreno 5000000.gpu: supply vddcx not found, using dummy regulator
[ 1.801167] msm_dpu c901000.display-controller: bound 5000000.gpu (ops a3xx_ops)
[ 1.813056] [drm] Initialized msm 1.13.0 for c901000.display-controller on minor 0
[ 1.905943] loaded qcom/a530_pm4.fw ... a530_pfp.fw ... a540_gpmu.fw2
[ 2.738653] fb0: msmdrmfb frame buffer device
```

GPUCC bound, GPU bound, aggregate DRM/KMS present, framebuffer created. The
approach of hooking the off-path instead of setting a static flag at provider
registration does preserve normal bring-up, as intended.

## Why the result is inconclusive

All four gate hits are at **1.35 s and 2.27 s** — probe-time collapses as the
Adreno driver powers the GPU down after init. After `fb0` at 2.738 s there is no
GPU activity whatsoever; the only later genpd line is
`[4.367798] PM: genpd: Disabling unused power domains`.

So the GPU never went runtime-idle again between 2.7 s and the reset at 17.8 s,
and the gate had nothing to intercept in the window that matters. **The late
collapse after `a5xx_pm_suspend()` returns success was never reached.** Any
claim that suppressing it does or does not prevent the reset is unsupported by
this boot.

## What did happen

```text
last console timestamp  [   17.835346]  EXT4-fs (mmcblk0p1): mounted filesystem
reached                 switch_root (11.51 s), udevd, root remount, boot part mount
ended                   abruptly, no panic / no oops / no BUG / no Unable-to-handle
reset class             ro.boot.product.lge.bootreasoncode = 0x20  (PS_HOLD)
qcom_icc_rpm_smd_send   0 occurrences (no -110 wedge; consistent, no vote-drop present)
```

Compare with the banked matrix: unpin-only died at **9.46 s** immediately after
`switch_root`; this boot passed that point and ran to **17.835 s**. That is a
real behavioural difference, not obviously timing noise — but with the target
transition unexercised, attributing the extra progress to the gate would be
speculation. It is recorded as an observation, not a conclusion.

## Caution for whoever reads the capture next

The `B - 567147 - PM: 0: PON=0x21 ... FAULT1=0x40:UVLO` lines near the top of the
pstore console are printed by **aboot at the start of the captured boot** and
describe the **previous** reset, not the one under investigation. `UVLO` there is
not evidence of a power fault in this run. The reset class for this run comes
from `ro.boot.product.lge.bootreasoncode` read from LineageOS afterwards: `0x20`.

IMEM cookies (`restart_reason`, sentinel, `crash_magic`) could not be read —
`scripts/read-imem-reset-reason.sh` needs root on LineageOS and adb `su` was
unavailable. Enabling rooted debugging would sharpen the next round.

## Suggested next step

The diagnostic infrastructure is sound and reusable; what is missing is a boot in
which the GPU actually goes runtime-idle *after* userspace. Options, in
increasing intrusiveness:

1. Exercise the GPU once from userspace, then let it idle, with the gate armed —
   turns the untested transition into a tested one using the same image.
2. Instrument `a5xx_pm_suspend()` entry/exit alongside the gate, so the log
   distinguishes "callback never ran" from "callback ran, collapse suppressed".
3. Only then re-run armed vs control (`joan_gpu_gate=0`) as a true A/B.

Do not treat this result as evidence that late GX/CX collapse is safe or
unsafe. It is neither.

## Do-not-repeat list (unchanged, plus one)

- Ember's gfx-mem ICC vote-drop candidate.
- Static `GENPD_FLAG_RPM_ALWAYS_ON` on initially-off `gpu_gx`.
- The clean SPTP-only unpin as if untested.
- A540 VBIF software reset.
- Any claim that TSIF `mas 35` is the GPU path.
- **New:** do not read the aboot `PON=`/`FAULT1=` lines in a pstore capture as
  the reset reason for that same boot.

---

## Addendum — control arm and deferred-probe-timeout test (same session)

Two further RAM boots, **same binary** as above, differing only in cmdline.

| Run | cmdline delta | `sync_state` lines | last coherent ts | outcome |
|---|---|---|---|---|
| gate1 | `joan_gpu_gate=1` | present @17.379 | 17.835 s | PS_HOLD reset |
| gate0 | `joan_gpu_gate=0` | present @17.121 | 17.122 s | PS_HOLD reset |
| dpt600 | `joan_gpu_gate=0 deferred_probe_timeout=600` | **0 (absent)** | 18.426 s | PS_HOLD reset |

### The gate makes no difference — GPU genpd collapse is not the killer

The control proves it with a same-binary comparison. With `gate=0` the markers
still logged and collapse actually **proceeded** at 1.35 s / 2.26 s, and the box
still ran to 17.1 s. Suppressing collapse (`gate=1`) neither saved it nor changed
the death window. Two conclusions:

1. Probe-time GX/CX collapse is *survivable* — it happens in the control and the
   boot continues for another ~15 s.
2. The earlier 9.46 s figure for unpin-only came from a **different binary**
   (`3d55e94d6`); this build reaches ~17-18 s regardless of gate state, so the
   apparent "extra progress" in the armed run was not the gate.

### deferred_probe_timeout was a false lead — recorded so nobody retries it

Both first runs died within ~0.7 s of the `sync_state() pending due to
1e40000.ipa` block, which looked causal. Pushing `deferred_probe_timeout` to 600
removed those messages **entirely** (count 0) and the phone died anyway, at
18.4 s. Correlation, not cause. Ruled out.

### What actually replicates

Across three cmdlines the death window is stable at **~17-18.4 s**, and in every
run it falls shortly after:

```text
EXT4-fs (mmcblk0p1): mounted filesystem a5d40a96-... r/w without journal
```

pmOS mounting its boot partition. No panic, no oops, no BUG in any capture;
console simply stops. Reset class `0x20` / PS_HOLD each time. That reproducibility
is the most useful thing this session produced — it is a fixed point to bisect
against, and it is not graphics.

### Capture hazard

The dpt600 ramoops dump contains entries stamped `552.9 s` and `710.6 s`
*after* an 18.4 s line. The timestamp sequence is non-monotonic (wrap at line
559) and the surrounding text is corrupt (`s_kvn_ggt`, `il!knvclkd stq|e 1`,
`MSM-SE^`). These are stale, partially-overwritten ring records from earlier
boots of the same kernel, **not** evidence that any boot survived 9 minutes.
Always check timestamp monotonicity before quoting a "last" line from ramoops.

### IMEM reset reason remains unreadable — and root is not the reason

We do have root on LineageOS (`uid=0(root) ... context=u:r:su:s0`, and
`adb exec-out dd` of the pstore block device succeeds). The blockers are:

- `/dev/mem` does not exist and, once created with `mknod`, returns
  `No such device or address` — the LineageOS kernel is built `CONFIG_DEVMEM=n`.
- `lge_handle_panic` exposes only panic **generators** (`gen_wdt_bark`,
  `gen_panic`, ... all `N`), no reader for the stored reason.

`scripts/read-imem-reset-reason.sh` reports "no read / no root", which is
misleading: it wraps every call in `sudo -n adb ... 2>/dev/null`, so a missing
passwordless sudo on the host silently presents as missing root on the phone.
Worth fixing the script rather than trusting its verdict.

### Suggested next step

Bisect against the reproducible ~17-18 s point rather than the GPU. The boot
partition mount is the last coherent milestone in all three runs; the next
question is what pmOS init does immediately after it, and whether the reset is
driven by that or by something asynchronous that merely lands there.
