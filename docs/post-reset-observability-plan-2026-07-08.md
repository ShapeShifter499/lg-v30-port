# LG V30 post-reset observability plan (2026-07-08)

Purpose: identify safe ways to extract more evidence after a failed RAM-only
mainline boot, without writing to the phone or triggering more firmware-side
crashes.

This is a no-code/source-and-readback audit. It is not a new kernel hypothesis
and it does not make another device boot worthwhile by itself.

## Executive summary

Safe/currently useful:

- `ro.boot.product.lge.bootreasoncode` remains the best proven low-risk
  post-reset signal from LineageOS.
- PMIC/PON readback through the existing harness remains useful for confirming
  PS_HOLD-style reset class.
- Listing `/sys/fs/pstore` is safe but currently not useful: it is mounted and
  empty after these tests.
- Source archaeology confirms downstream has an IMEM restart-reason path at
  `0x146bf000 + 0x65c`, but raw writes to this area are unsafe after K035.

Unsafe / do not use casually:

- **Do not read `/sys/kernel/debug/tzdbg/*` during routine probing.** The files
  are exposed by downstream `drivers/firmware/qcom/tz_log.c`, and they look like
  ordinary read-only debugfs files. However, Aurel's broad read-only probe reached
  `FILE:/sys/kernel/debug/tzdbg/boot`, then adb disappeared. After the phone came
  back, uptime was only about 43 seconds and `ro.boot.product.lge.bootreasoncode`
  had changed to `0x6D630309`. Treat tzdbg content reads as potentially
  reset-triggering on this LineageOS build unless Lance explicitly approves a
  controlled reproduction.
- Do not repeat K035's raw IMEM restart-reason write. It likely crashed LG/XBL's
  reset handler into Sahara/DXE_ASSERT.
- Do not rely on ramoops/pstore as a mainline crash channel unless a new
  persistence story is proven.

## Evidence handles from this audit

| Artifact | sha256 | Notes |
|---|---|---|
| `out/obs-readonly-lineage-probe.txt` | `343703caeac8c1d55f8d71640a618e94f24120e0fe975d5268490d0539d9ff1f` | broad read-only adb probe; saw pstore mounted+empty; saw tzdbg directory; adb vanished immediately after beginning tzdbg file read |
| `out/obs-tzdbg-readonly-detail.txt` | `6360f099d577cdff0bc2d4d28629a933b03e1ad6e545dbc76b7b3f3ed8fce00e` | follow-up as shell user; debugfs/tzdbg denied/missing, no content read |
| `out/obs-after-tzdbg-state.txt` | `4b049e91c22a644039a0c12da2235cdebfd489f774a8cb9dd84ad1cdcb098221` | post-event state: adb present, uptime ~43s, bootreasoncode `0x6D630309`, bootreason string `reboot`, boot complete |

Important timeline note: before the broad tzdbg read, the probe recorded
`ro.boot.product.lge.bootreasoncode=0x20` and `ro.boot.bootreason=bootloader`.
After the suspected tzdbg-triggered reset, the quick readback showed
`0x6D630309` and `reboot`. This makes the audit itself a cautionary finding, not
just a source survey.

## Existing observability evidence already known

From `docs/kernel-change-ledger.md`, `docs/bringup-debug-state-2026-07-06.md`,
and the K035/K041/K042 handoffs:

- `fastboot boot` is accepted from adb-entered bootloader.
- Mainline still fails before its USB gadget/debug channel appears.
- pstore/ramoops did not survive LG's boot chain usefully; even LOS-to-LOS warm
  paths lost content.
- K035's device photo showed LG firmware can display `tzbsp_reason` directly,
  and confirmed residual `0x6D630306` MM_NOC. That screen is valuable when it
  appears naturally, but trying to force it with IMEM writes is unsafe.
- K041 proved late Linux simplefb/fbcon does not provide useful on-screen
  console on joan's command-mode panel.
- K042 rejected SMMU cfg-probe subtraction and left no ready-to-test fix.

## Source findings

### LG restart reason / bootreason property

Relevant source:

- downstream `drivers/soc/qcom/lge/lge_handle_panic.c`
  - `RESTART_REASON_ADDR 0x65c`
  - maps `qcom,msm-imem@146bf000`
  - writes default `LGE_RB_MAGIC | LGE_ERR_TZ` during early init
  - exposes `lge_get_restart_reason()` as a kernel-internal read helper
- downstream `include/soc/qcom/lge/lge_handle_panic.h`
  - `LGE_RB_MAGIC 0x6D630000`
  - `LGE_ERR_TZ 0x0300`
  - `LGE_ERR_TZ_NON_SEC_WDT 0x0001`
- downstream `drivers/soc/qcom/lge/devices_lge.c`
  - parses `androidboot.product.lge.bootreasoncode=` into `lge_boot_reason`
- downstream `arch/arm/boot/dts/qcom/msm8998.dtsi`
  - `restart_reason@65c` compatible `qcom,msm-imem-restart_reason`

Implication:

- The Android property is the bootloader/kernel command-line representation of
  the IMEM restart reason and is safe to read through `getprop`.
- Reading IMEM through already-existing LineageOS paths may be safe; writing is
  not.

### TZ debug log (`tzdbg`)

Relevant source:

- downstream `drivers/firmware/qcom/tz_log.c`
  - creates debugfs dir `tzdbg`
  - files: `boot`, `reset`, `interrupt`, `general`, `vmid`, `log`, `qsee_log`,
    `hyp_general`, `hyp_log`
  - read path copies from TZ/HYP diagnostic memory via `memcpy_fromio()` and
    formats it for userspace
  - also registers a QSEE log buffer through SCM at probe
- downstream `arch/arm/boot/dts/qcom/msm8998.dtsi`
  - `tz-log@146BF720`, compatible `qcom,tz-log`, size `0x3000`
  - `qcom,hyplog-enabled`
  - hyp offsets `0x410` / `0x414`
- joan defconfigs enable `CONFIG_MSM_TZ_LOG=y`

Observed LineageOS behavior:

- `/sys/kernel/debug/tzdbg` exists and lists the expected files in the broad
  probe.
- Attempting to read content from `tzdbg/boot` likely reset the phone.
- A later non-root shell probe saw `Permission denied`/missing paths, so access
  may depend on adb shell context/SELinux timing; either way, content reads are
  now classified risky.

Implication:

- tzdbg is a tempting observability channel, but it is not safe enough for casual
  readback. If it is ever used again, it should be a single deliberate,
  Lance-approved device test with camera/host logging and no assumption that it
  is harmless.

### Pstore / ramoops

Relevant evidence/source:

- downstream joan defconfigs enable `CONFIG_PSTORE`, `CONFIG_PSTORE_CONSOLE`,
  `CONFIG_PSTORE_RAM`, and `CONFIG_LGE_PSTORE_BACKUP`.
- `/sys/fs/pstore` is mounted in LineageOS.
- Probe result: pstore directory was empty when readable; later shell read was
  permission denied.
- Existing ledger evidence says ramoops content does not survive LG's boot chain
  usefully.

Implication:

- Keep pstore checks in the harmless checklist, but do not spend more mainline
  kernel iterations trying to make ramoops the primary channel unless a new LG
  backup path is found.

### Qualcomm minidump / SMEM

Relevant source:

- downstream `drivers/soc/qcom/msm_minidump.c`
  - `SMEM_MINIDUMP_TABLE_ID 602`
  - reserves/updates a bootloader minidump table in SMEM
  - registers regions such as RTB, watchdog debug data, common log sections
- downstream `include/soc/qcom/minidump.h`
  - registration API only; no obvious userspace dump reader in this pass
- downstream defconfigs for joan do not obviously enable `CONFIG_QCOM_MINIDUMP`
  in the same way sdm660 defconfigs do, while several joan defconfigs do enable
  `LGE_PSTORE_BACKUP` and related LG debug features.

Implication:

- Minidump is more likely a bootloader/rawdump infrastructure than a safe
  LineageOS userspace file to query after normal PS_HOLD returns.
- Do not add minidump-driving code to mainline without first proving the installed
  LOS build exposes or preserves the relevant SMEM/minidump data read-only.

### edk2-msm8998

Relevant source findings from the prior handoff remain valid:

- edk2-msm8998 survives beyond the mainline reset window with a passive SoC
  bringup model.
- It uses UEFI console/display paths and includes Qualcomm binary DXE modules in
  board packages, but the source pass here did not find a clean read-only
  post-reset log path that LineageOS can query.

Implication:

- edk2 remains a good "minimal that survives" reference and possible manual
  console environment, but it is not yet a direct source for post-reset log
  extraction from Android.

## Safe command checklist

These are currently considered safe/read-only:

```bash
adb devices
adb shell getprop ro.boot.product.lge.bootreasoncode
adb shell getprop ro.boot.bootreason
adb shell getprop sys.boot_completed
adb shell cat /proc/uptime
adb shell 'ls -la /sys/fs/pstore 2>&1'
adb shell 'ls -la /sys/kernel/debug 2>&1 | head -120'
adb shell 'ls -la /sys/kernel/debug/tzdbg 2>&1'
```

Do not include `head`, `cat`, or other content reads of
`/sys/kernel/debug/tzdbg/*` in routine scripts.

## Conditional / Lance-approved only

Only if Lance explicitly approves a controlled observability experiment:

1. Ensure the phone is physically watched and recoverable.
2. Start host-side logging of `adb devices`, USB IDs, and selected properties.
3. Read exactly one tzdbg file, starting with the smallest/least likely to touch
   moving buffers, and stop immediately afterward.
4. If the device disappears or bootreason changes, classify the read path as
   destructive/risky and do not repeat.

Current recommendation: do **not** run this unless a future source clue says a
specific tzdbg file contains MM_NOC details unavailable elsewhere.

## Next technical criteria

Before another RAM-only mainline boot, require at least one of:

- a source-derived aggressive-init candidate analogous to K030 but not already
  cleared by K031/K042;
- a safe read-only post-reset channel that can distinguish MM_NOC subcauses
  without triggering its own reset;
- a manual/edk2/UART path that can show logs without touching TZ-owned debug
  regions from LineageOS.

If none of those exists, do not spend device cycles on another blind boot.

## Attribution

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-08
