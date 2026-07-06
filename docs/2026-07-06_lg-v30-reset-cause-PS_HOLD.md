# LG V30 reset-cause handoff — PS_HOLD secure-side reset

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

## Current headline

The LG V30 (`joan`) mainline reset is still a controlled PS_HOLD reset. The
secure/liveness hypothesis remains active, but Aurel has now rejected one more
specific first-second delta: downstream's DLOAD-off SCM argument shape.

## Evidence preserved from the PON / reset-cause pass

Baseline controlled bootloader chain and post-mainline-crash chain both report
SID0 power-off reason `PS_HOLD`:

```text
PMIC@SID0 Power-on reason: Triggered from Hard Reset and 'cold' boot
PMIC@SID0: Power-off reason: Triggered from PS_HOLD
PM: 0: PON=0x21:PON1:HARD_RESET: POFF=0x2:PS_HOLD: FAULT1=0x40:UVLO
lge.bootreason=NORMAL / bootreasoncode=0x20
```

Interpretation: the reset is hardware-indistinguishable from a deliberate secure
reset. It is not currently explained by PMIC watchdog, thermal bite, keypad/GP
fault, ordinary Linux panic, APSS watchdog node/petting, CPU-idle, secondary CPU
bringup, or high-memory secure/shared pool allocation.

## Concrete rejected paths so far

- `SEC_WDOG_DIS` via downstream/mainline/raw SMC variants: rejected. Downstream's
  own runtime sysfs path also failed with `0x42000107 ret=-2`.
- `panic=30`: rejected.
- APSS watchdog DT disable / downstream-style pet / EN=3: rejected.
- Single-core boot (`maxcpus=1`): rejected.
- CPU idle disabled (`cpuidle.off=1 nohlt`): rejected.
- Downstream high-memory secure/shared pool no-map reservation: rejected.
- IMEM oracle showed the useful readback route was PON/PS_HOLD, not LGE
  restart-reason decode.
- New in this update: downstream DLOAD-off SCM argument shape `(0, 0)`: rejected.

## New Aurel test: DLOAD-off SCM argument-shape oracle

Downstream reference:

- `android_kernel_lge_msm8998/drivers/power/reset/msm-poweroff.c`
- LGE builds default `download_mode = 0`.
- `pure_initcall(msm_restart_init)` calls `set_dload_mode(download_mode)`.
- For ARMv8 this calls SCM boot command `SCM_DLOAD_CMD` (`0x10`) with args
  `(0, 0)` for the off request.

Mainline delta:

- `linux-mainline-v30/drivers/firmware/qcom/qcom_scm.c`
- Mainline already calls SCM boot command `QCOM_SCM_BOOT_SET_DLOAD_MODE` (`0x10`),
  but for off it encoded args as `(0x10, 0)`.

Oracle:

- Patch:
  `out/aurel-latest-dload-off-argshape-test-2026-07-06.patch`
- Patch sha256:
  `eb285f2d73b2711fa505c0938183954b18ebb125735ae69176e7311fc8f1a5a0`
- Image:
  `out/boot-joan-latest-dload-off-argshape.img`
- Image sha256:
  `423d0c7f306a0d1617ade6577c8cb012df71cda6d6f8a08ab731dc4e79a26457`
- Size:
  `15736832` bytes

Result:

- RAM-only one-client `fastboot boot`.
- No flashing; no phone-storage writes; no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.516s`.
- No mainline USB/mass-storage/diag channel appeared.
- LineageOS adb returned at `t+44.3s`.
- Post-reset dmesg again showed SID0 `PS_HOLD`.

Conclusion: `SET_DLOAD_MODE` argument shape is not the missing liveness handshake.

## Next best single oracle

Try a QSEE/QSEEOS-side early ping, not bundled with watchdog or DLOAD changes.
The most concrete downstream target is:

- `android_kernel_lge_msm8998/drivers/firmware/qcom/tz_log.c`
- `tzdbg_register_qsee_log_buf()` allocates a QSEE log buffer from the qseecom
  ION heap and calls `SCM_QSEEOS_FNID(1, 6)` with args `(pa, len)` / arginfo
  `0x22`.
- `tzdbg_get_tz_version()` then queries TZ feature/version.

A mainline oracle could add a debug-only qcom_scm-probe call that performs only
one safe QSEE/TZ ping and measures whether reset timing or PS_HOLD behavior
changes. Preserve patch under `out/`, test by RAM-only `fastboot boot`, then
revert/rebuild clean and update the ledger.

## Caveat for expectations

If the reset is a secure watchdog/liveness service that can only be serviced from
signed TZ/aboot firmware, it may be unfixable purely from mainline Linux. The
US998 is unlocked, so there may still be a path, but do not promise one.

## Current state after Aurel update

- Kernel branch `joan/latest-clean-test` clean and rebuilt.
- Harness docs updated.
- Phone parked back in LineageOS.
- No fastboot client left running.
- No packages installed.
