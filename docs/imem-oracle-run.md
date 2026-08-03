# IMEM reset-reason oracle — run procedure

Prepped by Claude Code 2026-07-06. STAGED and ready; needs Lance + device.

## Idea in one line

Stop trying to prevent the ~27s reset; read the reset CAUSE the secure boot
chain records in IMEM SRAM (which survives the reset and is readable from
LineageOS — the channel ramoops couldn't be).

## What's staged

- Kernel branch `joan/imem-oracle` (off `joan/latest-clean-test`, commit
  `f0d368d28`). Adds a debug-only `early_initcall` that reads/logs the previous
  restart-reason, drops a "JOAN" sentinel, and writes a known default.
- Image: `out/boot-joan-imem-oracle.img`
  (sha256 `8d180d57b91aefae1d4fdbbb88cf138d76711866c7e5e3dcdceebc118fb768c7`).
- Readback helper: `scripts/read-imem-reset-reason.sh`.
- Patch backup: `out/imem-oracle-2026-07-06.patch`.

## Run it (Lance present)

Safety unchanged: RAM-only `fastboot boot`, one fastboot client, no flashing,
enter fastboot via `adb reboot bootloader`, do NOT use `fastboot getvar`.

1. Phone in LineageOS, adb visible, root enabled ("Rooted debugging").
2. OPTIONAL baseline read first (tells us the last reset's reason before we
   even boot the oracle):

       lg-v30-port/scripts/read-imem-reset-reason.sh

3. Send it to fastboot and RAM-boot the oracle (single client):

       adb reboot bootloader
       # wait for 18d1:d00d, then:
       fastboot boot out/boot-joan-imem-oracle.img

4. Let it do its usual thing: no mainline USB, ~27s reset, LineageOS returns.
   Do NOT force anything; the initramfs self-reboots if it ever hangs.
5. When LineageOS is back, read the reason our oracle-boot left behind:

       scripts/read-imem-reset-reason.sh

## Reading the result

- `restart_reason 0x146bf65c`:
  - `0x6d63033a` -> TZ non-secure watchdog **bark** (watchdog after all).
  - `0x6d63033b` -> TZ **thermal** secure bite (overheat/thermal path).
  - `0x6d630201` -> **RPM** subsystem.
  - `0x6d630301` -> **kernel**.
  - `0x6d630300` (our default, unchanged) -> the resetter records NO LGE reason
    -> suspect a raw **PMIC/PON or PS_HOLD** reset, not a TZ-logged watchdog.
- `sentinel 0x146bf640`:
  - `0x4a4f414e` ("JOAN") -> our early_initcall ran; the reset is AFTER it.
  - anything else -> reset precedes `early_initcall`; next oracle must write the
    cookie earlier (assembly in `head.S` / `setup_arch`, like the old
    breadcrumb, but into IMEM instead of the scrubbed ramoops region).

## Where each answer sends us next

- Named TZ watchdog bark -> revisit watchdog, but now we know it IS one; chase
  which counter and why downstream's pet path is refused (`-2`) on this unit.
- Thermal secure bite -> thermal config / TSENS on mainline; downstream thermal
  bringup diff.
- RPM -> RPM/SMD handshake or a regulator mainline misprograms; cross-check the
  captured downstream regulator table in `downstream-diag-2026-07-06.txt`.
- No LGE reason (default unchanged) -> PMIC PON/PS_HOLD: inspect pm8998
  `pon@800` + any PON watchdog downstream arms that mainline leaves untouched.

## After the round

Update `kernel-change-ledger.md` (fill in the observed reason + verdict),
`bringup-debug-state-2026-07-06.md`, internal mirror handoff, and the internal tracker. Keep
`joan/latest-clean-test` clean; the oracle lives only on `joan/imem-oracle`.

Assisted-by: Claude-Code:claude-fable-5
Date: 2026-07-06
