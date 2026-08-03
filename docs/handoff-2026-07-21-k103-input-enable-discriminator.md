# Technical handoff — K103 touch `input-enable` discriminator

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol[reasoning=max]
Provider/preset: `moa/oops-all-chatgpt-all-max`
Aggregator/acting model: `openai-codex:gpt-5.6-sol[reasoning=max]`
Reference routes: 2 × `openai-codex:gpt-5.6-sol[reasoning=max]`
Async delegation used for K103: none
Date: 2026-07-21

## State

**K103 is complete. Do not rerun it.**

- **Boot discriminator: PASS.**
- **Touch enablement: FAIL / unresolved.**
- **Final phone state: authorized LineageOS, `sys.boot_completed=1`.**
- One RAM-only `fastboot boot`; nothing was flashed.
- No automatic retry, no host timeout around the active fastboot client, no
  `pmbootstrap`, no push, and no public write.
- K104 is only a documented next diagnostic. It has not been prepared or run.

Run ID: `K103-20260721T163429Z`

## Controlled question

K102 introduced the ST FingerTipS node and failed during the observed device
run. K103 retained K102's kernel, ramdisk, command line, touch child node,
regulators, reset GPIO, interrupt, and pinctrl references, while deleting one
boolean property:

```dts
/soc@0/pinctrl@3400000/touch-int-default-state/input-enable
```

Normalized K102-to-K103 DT comparison contains exactly one deletion:

```diff
-				input-enable;
```

This is a one-way controlled discriminator, not a replicated K102/K103 A/B/A
sequence.

## Host qualification

Active image:

- path: `out/boot-joan-pmos-k103-touch-no-input-enable.img`
- SHA-256: `ae1bb3541f666cfb4ca2c8ef58eb9d3866d99a2302e7dc9785cf65b59aa67dc0`
- bytes: `26415104`

Source and DTB identity:

- clean source checkpoint:
  `16e3950bf9135070bd042ffc84e50e6ca7ebf468`
- source-built K103 DTB:
  `914f9f660bd81f7026a475c07eef77087733b6c1ea140c56319c7cf43fba0594`
- K102 parent DTB:
  `eb3100f714b3d6f56192c9de7d9049885df9d43b118354fec2fee666b492af92`
- clean-to-K103 patch:
  `out/k103-touch-no-input-enable-20260721/20260721-k103-touch-no-input-enable-from-clean.patch`
  (`c06e27ed3da6213d54c0ad862147a8e0ce0775d914d389e8d68be7b47bb22bb7`)
- K102-to-K103 patch:
  `out/k103-touch-no-input-enable-20260721/20260721-k103-k102-to-k103-touch-no-input-enable.patch`
  (`dcf9670469191d53ccd5c02f5cc39bb0d1f8b0edf59ef54eb8f130162099e750`)

Qualification gates passed:

- clean control DTB reproduced exactly;
- archived K102 patch reproduced the exact K102 DTB;
- two independent K103 builds produced the same source-built DTB;
- both patch routes passed `git apply --check` and produced identical source;
- normalized semantic comparison found only the property deletion above;
- parent-image repack round-tripped byte-for-byte;
- K103 retained K102's compressed/decompressed kernel, ramdisk, command line,
  load addresses, and other Android header fields; only appended DTB-derived
  kernel size and regenerated image ID changed;
- K101 quarantine image and marker remained intact.

The earlier libfdt/`fdtput` prototype is preserved under explicit
`SUPERSEDED-*` names and must not be used. It was semantically equivalent but
did not byte-reproduce from source.

## Single RAM-boot result

Host transcript:

```text
Sending 'boot.img' (25796 KB)  OKAY [0.588s]
Booting                       OKAY [5.100s]
Finished. Total time: 5.702s
FASTBOOT_BOOT_RC=0
```

The expected pmOS USB gadget (`18d1:d001`) appeared. SSH established:

- `uname`: `7.2.0-rc2-g16e3950bf913-dirty`
- root source: `/dev/mmcblk0p2`
- boot ID: `49cb55ea-194e-44fa-aa7e-3a5c1eec7c24`

The `-dirty` suffix is baked into this previously built kernel artifact. The
canonical kernel worktree remained clean at `16e3950bf9135070bd042ffc84e50e6ca7ebf468`
before and after K103.

Live DT inspection proved `input-enable` absent. The I2C/OF device at `0-0049`
was instantiated and `stmfts_probe()` ran. Probe then returned `-110`, unwound,
and no `stmfts` input device registered:

```text
stmfts 0-0049: probe with driver stmfts failed with error -110
```

Do not describe this as the touchscreen successfully binding.

## Conclusions and inference boundaries

### K103 boot discriminator: PASS

Deleting `input-enable` was sufficient to eliminate the observed K102 boot
failure in this controlled pair. K103 reached continuous pmOS userspace and
remained available for SSH diagnostics.

This does **not** establish the low-level K102 failure mechanism. K102 was not
replayed during this session, so the result is not a replicated A/B/A test.

### K103 touch enablement: FAIL / unresolved

Touch is not working. Probe returned `-110` and no touch input device
registered.

Mainline `stmfts.c` contains an explicit `-ETIMEDOUT` return while waiting for
a command-completion IRQ, but I2C, regulator, IRQ, or other lower layers may
also propagate `-110`. The exact command and stage are unproven without
instrumentation.

The later snapshot showed `touch_vdd` and `touch_avdd` disabled and no IRQ 125
listing. That snapshot was taken **after probe unwound**; it does not prove the
rails were never enabled or that no interrupt occurred during probe.

Joan's downstream FTM4 flow differs materially from mainline: it uses a
four-byte `B6 00 28 80` reset and polls `0x85` events. This is a strong
hypothesis for later investigation, not a proven root cause or fix. Power/reset
sequencing and IRQ behavior remain independent candidates.

The pmOS device wall clock was unset and reported 1969. Use host UTC, uptime,
and boot ID for chronology.

## Evidence bundle

Directory:

`out/k103-touch-no-input-enable-20260721/`

Key files:

- `K103-RESULT-20260721T163429Z.md`
- `k103-ramboot-20260721T163429Z.log`
- `k103-fastboot-transport-20260721T163429Z.txt`
- `k103-ssh-identity-20260721T163429Z.log`
- `k103-remote-readonly-diag-20260721T163429Z.log`
- `k103-dmesg-20260721T163429Z.log`
- `k103-live-rails-gpio-irq-20260721T163429Z.log`
- `k103-graceful-recovery-to-lineage-20260721T163429Z.log`
- `final-component-qualification.json`
- `PREBOOT-*` (byte-preserved host-only checkpoint)

Final manifest:

- `K103-FINAL-SHA256SUMS-20260721T163429Z`
- 46 verified entries
- detached manifest SHA-256:
  `2823bd3c81ddf20a63c153327584d56d63fab77c3ae1a4a87026396acd4bfcc2`
- detached verification-transcript SHA-256:
  `610363a9b9a6b6c08b37bd1db5bb365b61d8a891655426a89f02eb756ebb0eea`

The timestamped and convenience manifests and their verification transcripts
are excluded from manifest self-hashing. The active image is included as
`../boot-joan-pmos-k103-touch-no-input-enable.img`.

Credential-redaction exact-match scan over the finalized bundle and scoped
continuity documents: **0 occurrences**. Only `[REDACTED]` is retained where a
credential was used during graceful recovery.

## Recovery and final device state

A graceful reboot from pmOS returned the phone to persistent LineageOS without
using fastboot again:

- pmOS USB disappeared;
- LineageOS USB `18d1:4ee7` appeared;
- known ADB serial was authorized;
- `sys.boot_completed=1`;
- model `LG-US998`;
- no fastboot process remained.

Nothing was flashed.

## Next diagnostic — document only; do not execute from this handoff

Prepare a uniquely identified **K104 instrumentation-only** build. Instrument,
in order:

1. regulator-enable and reset-GPIO stages;
2. every STMFTS command opcode and I2C return;
3. command-completion wait entry and exit;
4. IRQ-handler entry;
5. raw event bytes read from the controller.

Do not combine a downstream-style protocol adaptation, IRQ-type change, and DT
change in one experiment. Identify the exact failing stage first, then test one
hypothesis at a time.

K101 remains quarantined. Never boot `out/boot-joan-mainline.img` (SHA-256
`494a7cfaf2e5fc2e9439718f7845f90a4956bed4cac68b114dc2cbeb0470a34c`).

The earlier timed-out delegation batch `deleg_8aa9de08` produced no final
findings and is not attributed as a K103 contributor; its unknown child model
routes are not invented here.
