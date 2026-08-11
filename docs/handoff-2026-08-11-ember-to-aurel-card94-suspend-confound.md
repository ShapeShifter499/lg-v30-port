# Handoff to Aurel — Card 94, 2026-08-11

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-11
For: Aurel Nymvale (agent-aurel)
State: READY FOR AUREL; four device runs banked; two hypotheses killed; one methodological correction; no fix promoted

## Read these first

1. `docs/ember-card94-staged-chain-confound-2026-08-11.md` — the important one
2. `docs/ember-a540-genpd-gate-result-2026-08-11.md` — device results + two addenda
3. Your own `docs/aurel-card94-a540-suspend-evidence-bank-2026-08-11.md` for the prior matrix

## Executive result

Your requested discriminator was built, ran cleanly on device, and **excluded
late GX/CX genpd collapse as the killer**. In the course of that, the staged
boundary-isolation chain that led to it turned out to be confounded. Two further
hypotheses of mine were tested and killed. The failure is reproducible and now
points somewhere other than the GPU's power path.

**The single most important item is the confound**, because it changes what the
prior chain establishes.

## The confound (please check my reasoning here)

Every staged A540 diagnostic returns `-EBUSY` from the runtime-suspend callback.
`-EBUSY` makes the PM core restore `RPM_ACTIVE` rather than complete the
transition, so **the GPU never suspended in any of those runs**. Your own
telemetry records it:

```text
clock-cycle result, every checkpoint to >5 min:
  runtime_status = active   suspended_time = 0   active_time -> 298,036 ms
vdd-cycle result:
  runtime_status=active     runtime_suspended_time=0
```

"Stable beyond five minutes" is therefore fully explained by the GPU staying
powered — the same condition the pin-present master control already
demonstrated. The individual stages are **untested**, and the inference that the
boundary had moved out to late genpd collapse does not follow from them.

Phase 8 is re-classified by the same logic: it survived 7 h 51 m because
`gpu_gx` never registered so the GPU never bound and never suspended, not because
the always-on flag protected anything.

One discriminator separates every result in the bank:

| Configuration | A540 completes a suspend? | Outcome |
|---|---|---|
| pin present (master) | no, `suspended_time=0` | stable 11+ min |
| Phase 8 (GPU unbound) | no | stable 7 h 51 m |
| all six staged `-EBUSY` tests | no, `active`, time 0 | stable >5 min |
| unpin-only | **yes** | dies 9.46 s |
| unpin + ICC vote-drop | **yes** | dies ~35 s |
| clean SPTP-gated unpin | **yes** | dies |
| my four runs, 2026-08-11 | **yes** | dies 17.1-19.9 s |

This correction is to an inference, not to your experimental work — the evidence
that exposes it is telemetry you recorded faithfully at every checkpoint.

## What I built

`93cc2be54` on `joan/a540-genpd-gate-test`, branched from your clean gated unpin
`9f3d891`, **not** from Phase 8. It hooks `gdsc_disable()` — which
`gdsc_register()` installs as `generic_pm_domain.power_off`, verified in-tree at
`gdsc.c:507` — and suppresses collapse of `gpu_gx` **and** `gpu_cx` together.

Gating GX alone would be unsound: `gpu_gx.parent = gpu_cx.pd`, so a child
reporting off makes the parent eligible to collapse, leaving GX physically
powered beneath a collapsed parent.

Armed with `joan_gpu_gate=1`, controlled with `joan_gpu_gate=0`, so **both arms
are the same binary**. Markers log in both arms *before* the gate is consulted,
so a gate that never fires is distinguishable from a gate that worked.

Your Phase 8 precondition failure is fixed by construction: hooking the off-path
rather than flagging at provider registration preserves bring-up. All four runs
bound GPUCC, the GPU and aggregate DRM/KMS, loaded a530/a540 firmware and
created `fb0`.

## Four device runs, one binary, cmdline-only variation

| Run | cmdline delta | key observation | last coherent ts |
|---|---|---|---|
| gate1 | `joan_gpu_gate=1` | gate fired 4x, suppressed | 17.835 s |
| gate0 | `joan_gpu_gate=0` | gate logged, collapse **proceeded** | 17.122 s |
| dpt600 | `+deferred_probe_timeout=600` | `sync_state` lines absent (0) | 18.426 s |
| clkignore | `+clk_ignore_unused` | `Disabling unused clocks` absent (0) | 19.874 s |

All four: PS_HOLD reset, `bootreasoncode=0x20`, no panic/oops/BUG in any capture.

**Killed hypothesis 1 — genpd collapse.** The control proves collapse *happened*
at 1.35/2.26 s and the box still ran to 17.1 s. Suppressing it changed nothing.
Probe-time collapse is survivable.

**Killed hypothesis 2 — deferred-probe timeout.** Both first runs died within
0.7 s of `sync_state() pending due to 1e40000.ipa`, which looked causal. Pushing
the timeout to 600 removed those messages entirely; death unchanged.

**Killed hypothesis 3 — a clock being disabled.** A DT audit found
`GCC_GPU_SNOC_DVM_GFX_CLK` (gcc 78) referenced by **no** `clocks =` property and
carrying no `CLK_IS_CRITICAL`, so `clk_disable_unused` killed it at 4.36 s in
every run — the same shape as the July `GCC_GPU_BIMC_GFX_SRC_CLK` bug.
`clk_ignore_unused` kept it (and everything else) enabled; death unchanged.

## Real wiring gaps found, not the cause, still worth fixing

Comparing against downstream `msm8998-gpu.dtsi`, mainline joan's GPU node lists
**7** clocks where downstream lists **8**:

- missing `isense_clk` (`gpucc_gfx3d_isense`) — downstream also sets
  `qcom,isense-clk-on-level = <1>`
- missing `iref_clk` (`gcc_gpu_iref`)
- plus the unclaimed `GCC_GPU_SNOC_DVM_GFX_CLK` above

Both missing clocks already exist in mainline's clock drivers, and
`msm_gpu.c:840` uses `devm_clk_bulk_get_all()`, so listing them is a DT-only
change. The GPU **SMMU** node matches downstream exactly (same three clocks) and
is *not* a gap. `vddcx` resolving to a dummy regulator is also **not** a gap —
CX is owned by `GPU_CX_GDSC` via genpd on this SoC, so the legacy regulator path
is vestigial.

These are worth landing on their own merits. They must not be promoted as a fix
for this failure, because `clk_ignore_unused` already excluded that mechanism.

## Where the evidence now points

All four runs die within about a second of:

```text
EXT4-fs (mmcblk0p1): mounted filesystem a5d40a96-... r/w without journal
```

`mmcblk0` is the **microSD card** — joan's internal storage is UFS
(`1da4000.ufshc`; LineageOS boots `root=/dev/dm-0 ... /dev/sda22`). So pmOS root
and boot live on SD, and the fatal moment is **SD-card I/O**, not graphics. Boot
1 of your original matrix already logged `SDCC bandwidth removal failed -110`.

Working hypothesis: a **completed** A540 runtime suspend degrades a shared
NoC/BIMC path, and the next heavy consumer of that path — SD I/O at the
boot-partition mount — trips the fault. It fits the pin-present control
performing the same mounts and surviving, because there the GPU never suspends.

Predictions worth testing:

1. pmOS rooted on **UFS** rather than SD should move or remove the death.
2. Heavy SD I/O forced *before* the GPU ever suspends should be harmless.
3. Instrumenting `a5xx_pm_suspend()` entry/exit would confirm the callback
   completes and time it against the mount.

## Pass criterion I would like adopted

Report `runtime_status` and `suspended_time` alongside survival time in every
A540 suspend result, and treat any run with `suspended_time = 0` as **not
executed** rather than as *stable*. Bisecting by *aborting* the callback cannot
work, because aborting it is itself the intervention that keeps the phone alive.
If a stage must be isolated, complete the callback and skip exactly one
operation while still returning **success**.

## Artifacts

Commits on `ember/bt-unconfigured-root-cause`, local only, nothing pushed:

```text
4409426  docs: Card 94 - clock-disable class ruled out; death tracks SD-card I/O
2c53c07  docs: Card 94 - staged boundary-isolation chain is confounded
0222421  docs: Card 94 addendum - gate ruled out, deferred_probe_timeout ruled out
87cc087  docs: bank Card 94 A540 late genpd gate device result
```

Kernel source: `93cc2be54` on `joan/a540-genpd-gate-test`, worktree
`linux-mainline-v30-a540-genpd-gate` (canonical tree untouched on
`joan/battery-fg`).

`out/` is git-ignored; this is the durable index.

```text
pstore-genpd-gate1-2026-08-11.bin  2097152  e7efa41d97a1d7955d988e576f5ad755dc4f5a51bce357051ff5b3e41f02f2fb
pstore-gate0-2026-08-11.bin        2097152  2e893bbfdcd73ffeff4bf8cb4e722ca777495866d1c43157efae6b9657b74af9
pstore-dpt600-2026-08-11.bin       2097152  dc4d910b37b03fe33a41743a197c9fae5e19d800653d39a89ad099c26eb74ec4
pstore-clkignore-2026-08-11.bin    2097152  8f50d6accf583cbefb114c4114885de88ac6e69f8c998d1a4ae0f1cda92040e4

boot-joan-a540-genpd-gate-93cc2be54-gate1.img   30535680  41d6ad8ee60b1d148e0af74164f5628b...
boot-joan-a540-genpd-gate-93cc2be54-gate0.img   30535680  4338ddb7c3be63f352f48632d15875c3...
boot-joan-a540-genpd-gate-93cc2be54-dpt600.img  30535680  b64e71ad52c7163c50fd7bd80854fd61...
boot-joan-a540-clkignore.img                    30535680  db9be1af3477a1cb455abec5f6e5fe94...

all four images: kernel 9be5071e57e83566..., ramdisk 43d1a861a694c40d... (identical)
```

Images are also on nym-nest under `~/joan-images/` for immediate re-runs.

## Reading hazards found the hard way

- The aboot `B - ... PON=0x21 ... FAULT1=0x40:UVLO` lines near the top of a
  pstore capture describe the reset **preceding** that boot, not the one being
  investigated. Do not quote them as its cause.
- The dpt600 capture contains entries stamped 552 s and 710 s *after* an 18.4 s
  line. The sequence is non-monotonic and the surrounding text is corrupt — stale
  ring records from earlier boots of the same kernel. Check monotonicity before
  quoting a "last" line.
- `scripts/read-imem-reset-reason.sh` reports "no read / no root" misleadingly:
  it wraps every call in `sudo -n adb ... 2>/dev/null`, so missing passwordless
  sudo *on the host* presents as missing root *on the phone*. We do have root
  (`uid=0(root)`, `adb exec-out dd` of the pstore block device works). The actual
  blockers are `CONFIG_DEVMEM=n` on the LineageOS kernel and `lge_handle_panic`
  exposing only panic **generators**, so IMEM cookies are unreadable from LOS
  regardless. Worth fixing the script's verdict.

## Device state

Phone is on LineageOS, nothing flashed, LineageOS untouched throughout. All work
was RAM-only `fastboot boot`. The Phase 8 boot was ended deliberately with
Lance's approval at 7 h 51 m uptime after a final state capture.
EOF
