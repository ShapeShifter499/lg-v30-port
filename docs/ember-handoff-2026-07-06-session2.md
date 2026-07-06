# Ember → Aurel handoff — joan reset hunt, session 2 (2026-07-06)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-fable-5
Date: 2026-07-06

## What this session added

Three things, in order of value:

1. **The reset is INDEPENDENT OF USERSPACE (K022, conclusive).** Booted the
   clean kernel + full joan DTB with a do-nothing init (no wdkill, no
   /dev/mem, no gadget). It still reset (~+33s, PS_HOLD). Every prior oracle
   ran the full bring-up init which pokes the APSS watchdog via /dev/mem
   (round 18 showed EN=0 there PROVOKES a reset) and brings up dwc3 — so no
   earlier result was clean. This confirms the whole handshake-parity line
   (K006-K021) is futile: nothing userspace does matters.

2. **Kernel USB/dwc3/QUSB2-PHY bring-up is NOT the trigger (K023b,
   conclusive).** Full joan DTS with only USB disabled, booted with
   **panic=0** (so a boot failure hangs silent instead of faking a reset).
   Still reset at +49s, PS_HOLD. USB eliminated.

3. **A reusable, boot-confound-free method + a caught false conclusion
   (K023).** First tried a fully-minimal DTB; it returned +49s which *looked*
   like "firmware timer confirmed," but an immediate-reboot proof-of-life
   proved the minimal DTB never reached userspace (early panic from
   over-stripping the RPM regulator block). Lesson now in the ledger and my
   memory: **a panic=N boot failure is indistinguishable from a reset by
   host-return timing; either use panic=0 (boot-fail => silent) or pair with
   an immediate-reboot proof-of-life.** K023b is the corrected, boot-safe
   pattern — reuse it.

## Current elimination table (what the ~27s PS_HOLD reset is NOT)

- not a normal Linux panic; not APSS watchdog (pet/disable/reprogram);
- not SEC_WDOG_DIS-serviceable (unimplemented, -2, even downstream);
- not single-core / cpuidle / high-mem allocation;
- not DLOAD arg-shape / QSEE logbuf / RPM reachability / BOB / L19 / L18+L19+BOB
  / TCSR DLOAD cookie / PON S3 / PON reset-seq / Kryo errata (all Aurel);
- **not anything userspace does (K022);**
- **not kernel USB/dwc3/PHY bring-up (K023b);**
- **not kernel UFS host/PHY bring-up (K023c).**

It IS: a controlled secure-side PS_HOLD reset (`POFF=0x2:PS_HOLD,
PON=0x21:HARD_RESET, FAULT1=0x40:UVLO` stale), ~27-49s window, and a
RAM-booted STOCK LG kernel does NOT reset (rounds 15-16) — so it is a real
mainline-vs-downstream KERNEL difference, not signing/unsigned-RAM-boot.

## Best next steps (boot-safe subtraction from full joan DTS)

Reuse the K023b harness exactly (image builder is trivial: full joan DTS
with one subsystem `status="disabled"`, classifier init, **panic=0**).
Subtract ONE at a time; if the reset stops, that subsystem's bring-up is the
trigger. Candidates, most promising first:

1. ~~UFS~~ — DONE (K023c), eliminated. USB (K023b) also eliminated.
2. **RPM regulators / rpm_requests** — but carefully: it's referenced by
   default nodes, so `status="disabled"` may break boot (=> silent with
   panic=0, which at least won't fool you). Consider disabling just the
   consumers, or accept the silent = "RPM needed to boot" datum.
3. **The whole `&soc` watchdog node** was already tried (no effect), so skip.
   Two big peripheral subsystems (USB, UFS) are now eliminated; the reset
   is looking less like ANY removable peripheral and more like a low-level
   secure/firmware timer. RPM is the last big untested removable — but
   likely breaks boot (=> silent with panic=0, still an honest datum).
4. If subtraction bottoms out (every removable subsystem still resets),
   the conclusion is a low-level secure/firmware timer armed at boot that
   downstream services via something below individual peripheral drivers
   (early SMC cadence, RPM master handshake, or a signed-TZ-only path) —
   at which point set expectations that mainline USB on joan may be blocked
   without deeper secure-side work. The unlocked US998 bootloader may still
   allow masking/extending it — worth a look before giving up.

## Method notes (binding, learned this session)

- **panic=0 for every subtraction test** — turns boot failures into silence,
  which is distinguishable from a reset (reset => LOS returns; boot-fail =>
  silent/hang). Do NOT use panic=N and read host-return timing as reset.
- Do NOT build up from a minimal DTB (it panics); subtract from the full one.
- Reset-cause channel: `qpnp-pon` regs in LOS dmesg after the crash
  (`Power-off reason`, `PON=0x`), read-only, no instrument. IMEM devmem is
  dead (no /dev/mem). ramoops is dead (LG scrubs it).
- One fastboot client; enter fastboot via `adb reboot bootloader`; no
  `fastboot getvar`; RAM-only; Lance present.

## State at handoff

- Kernel `joan/latest-clean-test` clean, 4 DTS commits ahead of v7.2-rc2.
- Harness repo clean. Artifacts: `out/ember-nousb-K023b-2026-07-06.dts`,
  `out/boot-joan-nousb-k023b.img`, `out/ember-mindtb-K023-2026-07-06.dts`.
- Phone in LineageOS, adb-visible, no fastboot client.
- Ledger K022 / K023 / K023b entries current; WebDAV + Deck #43 updated.
