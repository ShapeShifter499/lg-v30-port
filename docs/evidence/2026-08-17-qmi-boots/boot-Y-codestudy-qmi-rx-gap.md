# Boot Y code study: mainline never reads the ADSP's QMI requests — that's the wall (2026-08-18)

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:deepseek/deepseek-v4-pro
Date: 2026-08-18

## The mechanism, assembled from downstream slim-msm.c / slim-msm-ngd.c

1. On an NGD v2 system (msm8998) the ADSP is the SLIM manager. The app CPU's
   NGD driver is a message-pump + pipe-port programmer, NOT a core owner
   (confirmed by Boot X: core MMIO hangs by design).
2. The ADSP issues QMI requests to the app CPU over the SLIMbus QMI service
   (svc 0x0301): port assignment / pipe-port connect / disconnect. Downstream
   DRAINS them: slim-msm.c `msm_slim_qmi_recv_msg()` kthread worker, queued
   from `msm_slim_qmi_notify()` on QMI_RECV_MSG (lines 1395-1425).
3. On a CONNECT to the PGD logical address (pgdla, discovered via get_laddr
   with the PGD elemental address, slim-msm-ngd.c:557-575), downstream calls
   `msm_slim_connect_pipe_port()` (slim-msm.c:292): BAM/SPS pipe connect +
   `msm_hw_set_port()` PGD_PORT_CFGn/BLKn/TRANn programming, then rewrites
   the outgoing message port number to port_b (`puc[1] = pipes[].port_b`,
   slim-msm-ngd.c:671).
4. Mainline qcom-ngd-ctrl.c has the SEND side only (SELECT_INSTANCE, POWER,
   CHECK_FRAMER_STATUS). It has NO qmi_recv_msg, NO QMI_RECV_MSG handler,
   no registered rx message handlers for the ADSP's requests. The ADSP's
   pipe-port request is never answered.
5. Consequence: the ADSP waits for the app CPU's pipe-port work before
   completing the codec CONNECT_SINK; its TX stalls; 1.3 s later the ADSP
   watchdog fires and kills the system (Boot P's capture). The PGD port
   register writes being "silently ignored" (Boot Q) fit the same model —
   the port blocks only honor writes once the ADSP-coordinated assignment
   has happened, which mainline never performs.

## What the tree already has (JOAN debug params, default values)

- skip_select=false, slim_dbg=true, reconf_passthrough=false,
  portb_rewrite=true, pgd_prog=true, pgd_enable=false.
- pgd_prog's PGD_PORT_CFGn writes run BEFORE connect TX (qcom-ngd-ctrl.c
  ~line 990) — but without the ADSP-coordinated connect they are ignored.
- The reconfigure-range drop (MC 0x40-0x5F, MT_CORE) is CORRECT NGD
  behavior: downstream drops the identical range (slim-msm-ngd.c:430-432).
  reconf_passthrough is a dead end — retire it.

## Fix direction (Boot Y/Z)

Port the downstream QMI receive path into mainline qcom-ngd-ctrl.c:
1. qmi_handle with QMI_RECV_MSG notify -> kthread worker draining
   qmi_recv_msg, registered rx handlers for the ADSP->apps request messages
   of svc 0x0301 (find the exact message ids: downstream slimbus*_msg_v01
   structs in slim-msm.c cover select/power/framer; the port-management
   request structs are in the qmi headers / slim-msm-ngd.c callbacks).
2. Implement the pipe-port connect equivalent: PGD_PORT_CFGn(+BLKn/TRANn)
   programming only when the ADSP requests it, port_b rewrite, and the
   pgdla get_laddr discovery (QC_DEVID_PGD EA, eapc from DT).
3. Keep the core-MMIO hands off (Boot X lesson): never touch 0x200+.
4. A/B on device: boot qmidbg19x (or +1), start ADSP, aplay; watch for the
   QMI request rx log + the CONNECT_SINK completion instead of the stall.

## Evidence

- This file.
- Downstream refs: android_kernel_lge_msm8998/drivers/slimbus/slim-msm.c
  (lines 292-335 connect_pipe_port, 990-1072 data_port_assign,
  1395-1560 QMI recv), slim-msm-ngd.c (lines 430-432 reconfigure drop,
  555-575 pgdla + connect path, 658-671 port_b rewrite).
- Mainline refs: linux-mainline-v30-usb-otg/drivers/slimbus/qcom-ngd-ctrl.c
  (lines 22-150 params, 943-946 drop filter, 969-1010 connect TX + pgd_prog).
