# Null-init discriminator — run procedure

Prepped by Claude Code 2026-07-06. STAGED and ready; needs Lance + device.

## Why this, and why now

Every prior oracle (mine and Hermes Agent's ~15) was booted with the full bring-up
initramfs, which during the reset window:
  1. runs `wdkill`, writing the APSS watchdog registers at 0x17817000 via
     /dev/mem — and round 18 proved writing EN=0 there PROVOKES an earlier
     reset, so this is an active perturbation present in every result;
  2. brings up dwc3 + the USB PHY (configfs gadget, UDC bind).

So no prior test actually observed the phone's behaviour with Linux doing
NOTHING. The reset timing across Hermes Agent's runs also varies wildly (host cycle
~30s to ~108s). A fixed hardware watchdog resets on a fixed period; that much
variance smells like it's triggered by variable-timing userspace activity —
exactly what a do-nothing init removes.

This single test partitions the entire remaining hypothesis space.

## What's staged

- Kernel: unchanged clean `joan/latest-clean-test` (v7.2-rc2 + 4 DTS commits).
- Initramfs: `initramfs/root-null/` — mounts basics, touches NO hardware, NO
  /dev/mem, NO gadget; idles 0-150s; if alive at 150s brings up a distinct
  survivor beacon `18d1:5e30`; self-reboots at ~8min.
- Image: `out/boot-joan-nullinit-discriminator.img`
  (sha256 `ed00e7842b583eb2b12e68ef0f3f39512639590523db415a0bbea0719d837158`).

## Run it (Lance present)

Safety unchanged: RAM-only, one fastboot client, no flash, enter fastboot via
`adb reboot bootloader`, no `fastboot getvar`.

    adb reboot bootloader
    # wait for 18d1:d00d, then, single client:
    fastboot boot out/boot-joan-nullinit-discriminator.img
    # then watch USB for up to ~3.5 min

## Read the result (this is the whole point)

- **LineageOS adb (18d1:4ee7) returns at ~30-60s**  => the reset STILL happens
  with a do-nothing init. The resetter is a **background secure/firmware
  timer, independent of anything Linux userspace does.** Consequence: the
  entire "add a downstream liveness handshake" line (SEC_WDOG_DIS, QSEE, RPM,
  PON, TCSR, IMEM cookies, etc.) cannot fix it; any fix is secure-world /
  signed-firmware. STOP building handshake oracles. Reframe toward: can we
  even mask/extend it (unlocked US998 bootloader?), or is joan mainline USB
  simply blocked on this TZ.

- **Survivor beacon (18d1:5e30 "V30 NULLINIT SURVIVOR") appears at ~150s**  =>
  a do-nothing init SURVIVES the window a normal boot resets in. Then
  **something the normal init does triggers the reset.** Next passes bisect:
    1. null-init + wdkill only (no gadget)  -> tests the watchdog register writes;
    2. null-init + gadget only (no wdkill)  -> tests dwc3/PHY bring-up.
  Whichever reintroduces the reset is the trigger. This would be the first
  time the reset is pinned to a specific mainline action we control.

- **Neither within ~3.5 min** (total silence): ambiguous — likely survived but
  the beacon's UDC didn't bind (dwc3 never probed). Treat as "survived,
  no-USB", lean toward the survivor branch, and confirm by re-running with the
  beacon replaced by a `sysrq` reboot at 150s (a reboot you can SEE on the
  host = proof it lived that long).

## After the round

Fill the observed class into `docs/kernel-change-ledger.md` (entry K-NULL),
`bringup-debug-state-2026-07-06.md`, update the Claude Code handoff, internal mirror, and
the internal tracker. Kernel stays clean; this is initramfs-only, no kernel revert needed.

Assisted-by: Claude-Code:claude-fable-5
Date: 2026-07-06
