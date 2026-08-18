# Boot Q analysis: ADSP watchdog is the killer; PGD ownership is the missing piece (2026-08-17)

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:deepseek/deepseek-v4-pro
Date: 2026-08-17

## What Boot Q tested

Boot Q (qmidbg12q) = Boot P base + module-param-gated fixes in
qcom-ngd-ctrl.c:
- pgd_prog (default on): write PGD_PORT_CFGn/BLKn/TRANn before connect TX
- portb_rewrite (default on): rewrite the connect msg port to port_b
- reconf_passthrough (default OFF): stop dropping MC 0x40-0x5F messages
- timeout unwedge (always on): NULL pending DMA completions + reset the
  tx ring on TX timeout (also kills a latent use-after-free: a late DMA
  callback completing a dead stack completion)
- slim_dbg breadcrumbs: connect-path prints + timeout state dump
Plus pstore config (ramoops DT node already existed in joan.dts).

## Evidence (boot-Q-netconsole-crash.txt)

1. CONNECT_SINK still stalls: `TX timed out:MC:0x2d,mt:0x2` at t+379.0,
   `Tx:MT:0x2, MC:0x2d, LA:0xcf failed:-110`.
2. **The PGD cfg write did NOT persist**: at the timeout, ports 0..5 read
   cfg=0x0 (I wrote 0x51 before the TX). stat=0x72/0x82/.../0xc2 — the
   hardware has ALREADY assigned pipes 7..12 to ports 0..5 (stat bits
   4-11), matching downstream apps-ch-pipes 0x1f80. So port_b == pn for
   ports 0..5 (identity), and the register base/offsets are right.
3. int_stat=0x0 with int_en=0xfe000000: no TX_MSG_SENT, no NACK, no
   error — the NGD silently ate the message and stalled.
4. **The killer is the ADSP watchdog**: 1.3s after the stall:
   ```
   qcom_q6v5_pas 17300000.remoteproc: watchdog received: SFR Init: wdog or kernel error suspected.
   remoteproc remoteproc1: crash detected in adsp: type watchdog
   ```
   The DSP's audio task hangs waiting on the SLIM connect handshake,
   its watchdog bites, PDR recovery starts, and the codec's internal
   SoundWire fails to reconnect (`link failed to connect`). System then
   dies (warm reset to LineageOS).
5. Also: the connect-path breadcrumb print did not appear in the capture
   — either netconsole dropped it under the glink print flood or the
   message did not take the rewrite path. The timeout-recover dump DID
   arrive, so netconsole was healthy at the timeout. Open question,
   revisit if Boot R still stalls.

## Root cause of the ignored PGD write

Mainline never enables the PGD or claims port ownership. Downstream
controller enable (slim-msm-ctrl.c ~1330-1370) writes, in order with
mb() barriers: framer enable, MGR_CFG enable, INTF_CFG=1,
**PGD_CFG=1 (0x800)**, **PGD_OWN_EEn += 0x3F<<17 (0x300C + 4*ee,
ee=1)** — claiming ports 0..5 — then COMP_CFG=1.

Without PGD_CFG + ownership, PGD_PORT_CFGn writes are ignored by the
hardware (observed: cfg reads back 0), the manager cannot complete the
connect, the DSP watchdogs, the bus dies.

## Boot R patch

In qcom_slim_ngd_power_up(), after qcom_slim_ngd_setup():
```
writel_relaxed(1, ctrl->base + PGD_CFG_V2);
writel_relaxed(0x3F << 17, ctrl->base + PGD_OWN_EEn_V2 + 4 * 1);
mb();
```
with a readback breadcrumb. Everything else from Boot Q stays
(pgd_prog, portb_rewrite, unwedge, slim_dbg, pstore).

If Boot R still stalls: reconf_passthrough=1 is the next toggle
(cmdline-settable: qcom_ngd_ctrl.reconf_passthrough=1), then check
whether the connect-path breadcrumb prints (did the rewrite path run?).

## Ledger

K192-K19x: append after Boot R. (See kernel-change-ledger.md.)
