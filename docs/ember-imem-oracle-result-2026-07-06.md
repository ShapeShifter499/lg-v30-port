# LG V30 joan — reset-cause finding (Ember, 2026-07-06)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-06

## Headline

The ~27s reset is a **clean, TZ/secure-side PS_HOLD reset** — hardware-
indistinguishable from a deliberate reboot. No PMIC watchdog, no thermal
bite, no GP/keypad fault. This is positive evidence it is a *secure-world
commanded* reset, not a hardware watchdog timeout or overtemp.

## How we got it (the channel that finally works)

The IMEM-devmem oracle idea was a DEAD END on-device: this LOS kernel has
**no /dev/mem** (confirmed), so IMEM 0x146bf65c cannot be read from LOS.
BUT a free, zero-instrumentation channel exists: the downstream `qpnp-pon`
driver prints the PMIC power-on/power-off/FAULT registers at every boot,
and those registers latch the LAST reset cause. So: RAM-boot mainline,
let it reset, then read the PON registers from the LOS that comes back.

Method (no kernel changes needed): `scripts/read-imem-reset-reason.sh` is
now superseded by simply grepping LOS dmesg for `qpnp-power-on` / `PON=0x`.
Full capture: `docs/pmic-pon-pass-2026-07-06.txt`.

## The data (single clean pass, v7.2-rc2 joan/latest-clean-test image)

Baseline (controlled `adb reboot bootloader` chain):
```
PMIC@SID0 Power-on reason: Triggered from Hard Reset and 'cold' boot
PMIC@SID0: Power-off reason: Triggered from PS_HOLD
PM: 0: PON=0x21:PON1:HARD_RESET: POFF=0x2:PS_HOLD: FAULT1=0x40:UVLO
```
After mainline crash-reset (~46s host cycle, LOS returned):
```
PMIC@SID0 Power-on reason: Triggered from Hard Reset and 'cold' boot
PMIC@SID0: Power-off reason: Triggered from PS_HOLD
PM: 0: PON=0x21:PON1:HARD_RESET: POFF=0x2:PS_HOLD: FAULT1=0x40:UVLO
lge.bootreason=NORMAL / bootreasoncode=0x20
```
**Identical.** (FAULT1=0x40:UVLO is present in BOTH, i.e. a stale latch,
not the cause.)

## Interpretation

PS_HOLD deassertion is how the MSM/secure side performs a *controlled*
SoC reset (PSCI SYSTEM_RESET, TZ monitor, or a secure-watchdog bite all
route through TZ pulling PS_HOLD). The absence of any PMIC fault flag
means it is NOT: PMIC hw watchdog, OTST/overtemp, KPDPWR, GP1/GP2, or a
power fault. Combined with prior rejected experiments (SEC_WDOG_DIS is
unimplemented -> returns -2; APSS pets/disable no effect; not panic; not
CPU/idle; not high-mem):

**Leading hypothesis:** a TZ/secure-world supervisor commands the reset
at ~27s because mainline never establishes some secure-side liveness /
handshake the LG boot chain expects. It is a *policy/handshake* reset,
not a fault or a serviceable non-secure watchdog.

## Suggested next moves (for whoever runs the next device pass)

1. Confirm timing tightness: is it ALWAYS ~27s, or load-dependent? A fixed
   period argues for a secure watchdog/timer; variance argues for a
   triggered policy check.
2. Look at what downstream does in secure-world liveness during 0-1s that
   mainline omits: `scm_call` pings, `qcom,scm` "SET_DLOAD_MODE", the
   qseecom/tzapp bring-up, or an RPM/AOP handshake. Diff downstream dmesg
   0-1s vs mainline (we only have downstream side).
3. Test the PSCI angle directly: does mainline's PSCI SYSTEM_RESET produce
   this SAME PS_HOLD signature? (It should — confirms our read is the reset
   path, and that the culprit uses the standard secure reset.)
4. If it is a secure watchdog only serviceable from TZ, this may be
   **unfixable without a signed TZ/aboot change** on a locked H932-style
   secure boot — set expectations. The US998 is unlocked; check whether an
   unlocked-bootloader path lets us mask/extend it.
5. Cross-check: on the running LOS, what pets/keeps the platform alive that
   we can identify (qcom_wdt? rpm? a secure daemon)? Downstream diag already
   captured in `downstream-diag-2026-07-06.txt`.

## Housekeeping

- IMEM oracle (`joan/imem-oracle`, commit f0d368d28, image
  `out/boot-joan-imem-oracle.img`) is PRESERVED but its readback method is
  moot (no /dev/mem). Keep for reference; the PON-register read replaces it.
- Kernel `joan/latest-clean-test` clean, rebuilt. No flashing, no writes.
- Phone parked in LineageOS, adb-visible.
