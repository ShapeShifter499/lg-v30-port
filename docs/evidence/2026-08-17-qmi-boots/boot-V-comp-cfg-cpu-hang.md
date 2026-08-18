# Boot V: COMP_CFG write hangs CPUs — RCU stall captured (2026-08-17)

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:deepseek/deepseek-v4-pro
Date: 2026-08-17

## Summary

Boot V (qmidbg17v) = Boot U base + pgd_enable=1 via cmdline
(slim_qcom_ngd_ctrl.pgd_enable=1) + the full downstream component-level
init sequence (COMP/TRUST/MGR/FRM/INTF/PGD/OWN) with per-step breadcrumbs.
Netconsole attached BEFORE the ADSP start — the first capture of the
hang mechanism.

## Evidence (boot-V-netconsole-stall.txt)

1. power_up entered (91.01s) -> NOTHING from the sequence (no step
   prints) -> "Rcvd master capability" (91.03s, RX path independent).
2. t+112s: RCU stall detected; CPUs 3 and 4 unresponsive to NMI (10s
   retries) — the COMP_CFG write (step 1) hard-hung two CPUs.
3. t+132s: RCU GP kthread starvation + NMI backtraces; the system
   otherwise KEEPS RUNNING (display alive with dpu frame-event
   overflows at 147s+, ssh/usb/touch survive — Lance's observation:
   first boot in a while that didn't kill the UI/USB).
4. t+630s: further backtraces (el0_svc) as the stall degrades things.

So the previous wedges (Boots R/S/T — stuck UI, dead ssh/usb) were
this same CPU hang spreading; without early netconsole we only ever
saw the symptoms.

## Why the write hangs (theory now testable)

Downstream writes COMP_CFG FIRST, BEFORE enabling the manager/NGD
(slim-msm-ctrl.c: COMP+TRUST -> MGR ints -> MGR cfg -> FRM ->
MGR enable+msgq -> INTF -> PGD+OWN -> COMP). Boot V ran the sequence
AFTER qcom_slim_ngd_setup() had already enabled the NGD — writing
COMP_CFG to a live controller. Boot W reorders: component init first,
then setup().

Also ruled out: the "missing SLIM clock" theory — mainline has no
slimbus clock in gcc-msm8998.c AND gcc-sdm845.c (db845c works
upstream without one), and the downstream 8998 clock tree has no
slim clock registration either. The clock is not the differentiator.

## Boot W (qmidbg18w)

- pgd_init moved BEFORE qcom_slim_ngd_setup() in both power_up
  branches; master_worker call removed (would re-hit the live
  controller).
- Same per-step breadcrumbs: a hang now pinpoints the exact register.
- Same cmdline: slim_qcom_ngd_ctrl.pgd_enable=1.

## Ledger

K19x: to append after Boot W.
