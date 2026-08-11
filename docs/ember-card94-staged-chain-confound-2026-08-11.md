# Card 94 — the staged boundary-isolation chain is confounded

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-11
For: Aurel Nymvale (agent-aurel), Lance
State: METHODOLOGICAL CORRECTION; no fix promoted; no new boot required to reach it

## Claim

The staged A540 suspend-path diagnostics do **not** clear the driver-local
stages. Every one of them returns `-EBUSY` from the runtime-suspend callback,
which leaves the device `RPM_ACTIVE`. The GPU therefore never suspended in any
of those runs, and "stable beyond five minutes" is fully explained by that alone
— it is the same condition the pin-present master control already demonstrated.

This is a correction to an inference, not to the experimental work. The evidence
needed to catch it was recorded faithfully in Aurel's own result documents; the
telemetry below is his.

## The evidence, from the staged results themselves

`aurel-a540-clock-cycle-result-2026-08-10.md`:

```text
| checkpoint | runtime_status | runtime_usage | active_time  | suspended_time |
| immediate  | active         | 0             |  33,295 ms   | 0              |
| ~2 min     | active         | 0             | 116,268 ms   | 0              |
| >5 min     | active         | 0             | 298,036 ms   | 0              |
```

`runtime_status` never leaves `active`; `suspended_time` never leaves `0`;
`active_time` climbs monotonically to ~298 s. The GPU was powered for the entire
observation window.

`aurel-a540-vdd-cycle-result-2026-08-10.md` records the same directly:
`runtime_status=active`, `runtime_suspended_time=0`.

And the mechanism is explicit in the designs, e.g. clock-cycle step 8: *"return
`-EBUSY` before `disable_pwrrail()`"*; post-vbif: *"returned `-EBUSY` immediately
after the A540 GDSC gate"*. `-EBUSY` from `->runtime_suspend` causes the PM core
to restore `RPM_ACTIVE` and retry later rather than completing the transition.

## Why this matters

Each staged test was read as "this stage is safe, advance to the next". The
alternative reading — "the callback aborted, so the GPU stayed powered, so the
phone lived" — predicts exactly the same observation, and is the one the
telemetry supports. The stages are therefore **untested**, individually and
cumulatively, and the conclusion that the boundary had been pushed out to late
genpd collapse does not follow.

## Every result in the bank fits one discriminator

| Configuration | A540 completes a runtime suspend? | Outcome |
|---|---|---|
| pin present (master control) | no — `suspended_time=0` | stable 11+ min |
| Phase 8 `GENPD_FLAG_RPM_ALWAYS_ON` | no — GPU never bound | stable 7 h 51 m |
| pre-VBIF / post-VBIF / devfreq / AXI / clock / vdd stages | no — `-EBUSY`, `active`, time 0 | stable >5 min |
| unpin-only | **yes** | dies 9.46 s |
| unpin + gfx-mem ICC vote-drop | **yes** | dies ~35 s, plus RPM `-110` |
| clean SPTP-gated unpin | **yes** | dies |
| genpd gate armed / control / dpt600 (2026-08-11) | **yes** | dies 17.1-18.4 s |

Everything that stays alive has a GPU that never completed a suspend.
Everything that dies has one that did. No other variable separates the two
groups.

## What our 2026-08-11 runs add

Ours are the first builds in which the callback **completed successfully** — no
`-EBUSY` — and the box still died, with genpd collapse suppressed on one arm and
permitted on the other, to no effect. Combined with the above:

- the fatal transition is **inside a successfully completed
  `a5xx_pm_suspend()`**, not in the genpd collapse that follows it; and
- no experiment to date has exercised that completed callback in isolation,
  because every staged test aborted it.

Phase 8 is also re-classified by this: it stayed up 7 h 51 m not because a
static always-on flag protected anything, but because the GPU never bound and so
never suspended. Same confound, different mechanism.

## Suggested next discriminator

Stop bisecting by *aborting* the callback, because aborting it is itself the
intervention that keeps the phone alive. Instead let it complete every time and
vary one operation inside it, e.g.:

1. Complete the callback but skip exactly one stage (VBIF halt, or devfreq, or
   AXI/EBI, or clock disable, or the regulator vote), returning **success**.
2. Require `suspended_time > 0` in the pass criteria — a run where the GPU never
   suspended must be recorded as *not executed*, not as *stable*.
3. Keep the cmdline-toggle discipline so both arms are the same binary.

Point 2 is the important one. Any future A540 suspend result should state
`runtime_status` and `suspended_time` alongside the survival time, and a run with
`suspended_time=0` should not count as evidence about any stage.

## Standing caution

"Stable" is only meaningful once the thing under test is shown to have happened.
This is the same failure mode as a diagnostic gate that never fires: absence of
the intervention is indistinguishable from success of the intervention unless
something positively records that it ran.
