# Boots R/S/T: PGD enable/ownership writes HANG the controller (2026-08-17)

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:deepseek/deepseek-v4-pro
Date: 2026-08-17

## Summary

The PGD_CFG (0x800) + PGD_OWN_EEn (0x300C+4*ee) writes that downstream
performs during controller enable HANG the NGD on current mainline.
The hang signature: the write never completes (the following breadcrumb
print never fires), the codec never enumerates (no soundcard), and the
system progressively wedges (ssh banner timeout while ping works,
then the USB gadget dies).

## Boot matrix (RAM-only, nothing flashed)

| Boot | PGD writes | Result |
|---|---|---|
| Q qmidbg12q | port cfg only (0x51 per port) | ports cfg read back 0 (ignored); connect stalls; ADSP watchdog = death. No wedge otherwise. |
| R qmidbg13r | PGD_CFG/OWN in power_up REINIT branch only | first bring-up takes the ADSP-framer LADDR branch (writes skipped); healthy; late wedge (~15 min) consistent with a later resume hitting the reinit branch |
| S qmidbg14s | hoisted: both power_up branches | power_up ran (T's breadcrumb proves the path); capability arrived via RX; then wedge (no soundcard reached) |
| T qmidbg15t | + master_worker call | power_up breadcrumb fired; "Rcvd master capability" fired; pgd_init print NEVER fired (write hung the workqueue); no soundcard; wedge |

## Conclusion

- Downstream writes PGD_CFG=1 + PGD_OWN_EEn|=0x3F<<17 (ee=1) inside a
  full init sequence: framer enable -> MGR_CFG enable -> INTF_CFG=1 ->
  PGD_CFG=1 -> OWN bits -> COMP_CFG=1, each with mb(). Mainline's
  qcom_slim_ngd_setup() only touches the NGD_CFG + msgq enables, so the
  PGD registers are not ready for those writes.
- The port-level PGD_PORT_CFGn writes (Boot Q) are silently IGNORED
  (cfg reads back 0, no hang) — different sensitivity class.
- The connect-sink stall remains the open wall: without the ownership
  claim the manager never completes CONNECT_SINK, and the ADSP
  watchdogs ~1.3 s later.

## Next steps (Boot U / next session)

1. Boot U (qmidbg16u): pgd_enable param (default OFF) so the phone is
   usable; all experiments stay cmdline-driven
   (qcom_ngd_ctrl.pgd_enable=1 etc.).
2. Code study (no phone needed): port the downstream init sequence
   order into mainline — read slim-msm-ctrl.c msm_slim_ctrl... enable
   path (FRM_CFG / MGR_CFG / INTF_CFG / COMP_CFG register values at
   0x... on the joan base) and compare with qcom_slim_ngd_setup +
   qcom_slim_ngd_power_up; identify exactly which prerequisite write
   un-hangs the PGD (likely the framer/MGR/INTF enables, or the QMI
   select-instance state the downstream reaches first).
3. Candidate ordering for one-boot A/B with netconsole + breadcrumbs.
4. Watch the no-playback wedge too: Boots R/S/T wedged without any
   playback; Q did not. Correlates with the PGD writes, but confirm on
   U (writes gated off).

## Evidence files

- docs/evidence/2026-08-17-qmi-boots/boot-P-netconsole-crash.txt
- docs/evidence/2026-08-17-qmi-boots/boot-Q-netconsole-crash.txt
- docs/evidence/2026-08-17-qmi-boots/boot-P-slim-connect-stall-analysis.md
- docs/evidence/2026-08-17-qmi-boots/boot-Q-adsp-watchdog-pgd-ownership.md
