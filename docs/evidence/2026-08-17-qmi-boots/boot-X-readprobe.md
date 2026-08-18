# Boot X: userspace read-probe — core blocks hang on READ; controller is V2 NGD (2026-08-18)

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:deepseek/deepseek-v4-pro
Date: 2026-08-18

## Setup

- Image: boot-joan-qmidbg19x.img (sha256 f2fd7f28..., 29,995,008 B)
- Kernel: 7.2.0-rc2-g29234a4d22a0-dirty (same tree as Boot W), STRICT_DEVMEM=n,
  slim_qcom_ngd_ctrl.pgd_enable=0 in cmdline.
- Probe: static aarch64 /dev/mem tool (mmap + volatile read/write), per-probe
  `timeout 2`, taskset CPU0, run BEFORE the ADSP start.
- Offsets: base 0x171c0000 + {0x004, 0x200, 0x400, 0x600, 0x800, 0x1000,
  0x3000, 0x14000}.  (Note: +0x14000 = 0x171d4000.)

## Results

1. `0x171c0004` (COMP_CFG, V2 offset 4): READ OK, value 00000000.
   The first page is accessible; no unclocked/protected fault.
2. `0x171c0200` (MGR_CFG): READ wedges the system permanently. The probe
   process could not be recovered by the 2s SIGKILL; USB gadget died within
   the 150s window; phone stopped answering ping. The wedge did not print
   anything to netconsole (usb0 died first).
3. Control: the v1 probe run (buggy address math) read 8 garbage unmapped
   addresses (~0x171c0000000, 1.5 TB). Each read hung its core >2s but the
   system RECOVERED after SIGKILL every time. Therefore the 0x200 wedge is
   register-specific, not generic unmapped-MMIO behavior.

## Register map (downstream android_kernel_lge_msm8998, drivers/slimbus)

- slim-msm.h CFG_PORT(r,v): offsets are version-dependent. V1: COMP_CFG=0,
  TRUST=0x14, PGD_CFG=0x1000, PGD_PORT_CFGn=0x1080. V2: COMP_CFG=4,
  TRUST=0x3000, PGD_CFG=0x800, PGD_OWN_EEn=0x300C, PGD_PORT_CFGn=0x14000.
- Every zone behavior observed across Boots Q-X matches the V2 map exactly
  (0x14000 silently ignored, 0x800/0x300C hang, 0x4 readable) =>
  the joan SLIM controller is V2. Version register at base+0x0 (read dev->base
  >> 16) still needs an explicit confirm read (safe: first page reads OK).
- The component-init sequence (COMP_CFG -> TRUST -> MGR -> FRM -> INTF ->
  PGD -> OWN -> COMP) lives in slim-msm-ctrl.c, the NON-NGD manager driver
  (app CPU owns the core; e.g. older SoCs). msm8998.dtsi binds
  `qcom,slim-ngd` for slim@171c0000 => slim-msm-ngd.c, and the downstream
  NGD driver does NOT write COMP_CFG/MGR_CFG. It only touches
  PGD_PORT_CFGn (line 662) and PGD_PORT_INT_ST_EEn (line 159) — after the
  ADSP has assigned the ports.
- Conclusion: on this NGD system the SLIM core (MGR/FRM/INTF/PGD blocks) is
  OWNED BY THE ADSP. Direct app-CPU MMIO to 0x200+ hangs by design.
  Boots R-W ported a non-NGD init sequence onto an NGD system; the hang was
  the hardware refusing foreign ownership. That direction is REJECTED.

## Boot Y plan

1. Confirm read of base+0x0 (version word, expect nonzero V2 marker) and
   base+0x3000 (COMP_TRUST_CFG_V2) on the same qmidbg19x image. First-page
   reads are safe; do NOT probe 0x200+ again.
2. Pivot to the message path. The app CPU's legitimate core access is via
   the ADSP: NGD DMA + QMI (service 769) + SLIM reconfigure messages.
   Restore the dropped reconfigure message range (MC 0x40-0x5F) —
   the parked Boot Q candidate — and study slim-msm-ngd.c's
   get_ch_mapping/port assignment flow vs mainline qcom_slim_ngd_ctrl.c.
3. The CONNECT_SINK stall (Boots P+) is most consistent with: port_b
   programming never reaches the ADSP manager because mainline drops or
   never sends the reconfigure/port-assign messages the firmware expects.

## Evidence files

- This file.
- /tmp/joanrun/bootx/probe-qmidbg19x.txt (v1 buggy run, garbage addresses)
- /tmp/joanrun/bootx/probe-qmidbg19x-v2.txt (v2 run: 0x004 read OK, 0x200 wedge)
- netconsole-qmidbg19x.txt (empty — USB died before any print)
- Images staged on nest: ~/joan-images/boot-joan-qmidbg19x.img; tooling in
  ~/joan-images/staging/qmidbg19x/ (devprobe, probe-x.sh, nest-bootx.sh,
  repack-qmidbg19x.sh)
