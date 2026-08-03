# Technical handoff — hardware-migration pause after K103

Assisted-by: Hermes-Agent:openai-codex/gpt-5.6-sol[reasoning=max]
Provider/preset: `moa/oops-all-chatgpt-all-max`
Aggregator/acting model: `openai-codex:gpt-5.6-sol[reasoning=max]`
Reference routes: 2 × `openai-codex:gpt-5.6-sol[reasoning=max]`
Async delegation used for this preservation task: none
Date: 2026-07-21

## State

**PAUSED BY LANCE FOR HARDWARE MIGRATION — DO NOT AUTO-RESUME.**

This is a preservation handoff, not a new hardware experiment. Do not prepare
or run K104, rebuild an image, invoke pmbootstrap, access the phone, run ADB or
fastboot, switch branches, merge/pull remote history, clean source trees, or
push anything until Lance explicitly resumes the LG V30 project.

K103 is complete and must not be rerun. The last device state verified during
K103 was fully booted, authorized LineageOS. That is a historical last-verified
state; this preservation pass did not query the phone. Nothing was flashed.

Canonical technical handoff:

`docs/handoff-2026-07-21-k103-input-enable-discriminator.md`

## K103 resume anchor

- exact K102-to-K103 semantic delta: deletion of
  `touch-int-default-state/input-enable`;
- one RAM-only K103 boot reached postmarketOS from microSD;
- `stmfts_probe()` returned `-110` and no touch input device registered;
- exact timeout stage and the low-level K102 mechanism remain unresolved;
- active K103 image:
  `out/boot-joan-pmos-k103-touch-no-input-enable.img`;
- active image SHA-256:
  `ae1bb3541f666cfb4ca2c8ef58eb9d3866d99a2302e7dc9785cf65b59aa67dc0`;
- sealed K103 evidence directory:
  `out/k103-touch-no-input-enable-20260721/`;
- final 46-entry K103 manifest SHA-256:
  `2823bd3c81ddf20a63c153327584d56d63fab77c3ae1a4a87026396acd4bfcc2`;
- K103 docs commit before this handoff:
  `2c4dec2aef2fcd00e513131d83f48566b0d2db34`, SSH-signed, local, unpushed.

Do not alter or regenerate the sealed K103 evidence bundle. Its verification
transcript SHA-256 is
`610363a9b9a6b6c08b37bd1db5bb365b61d8a891655426a89f02eb756ebb0eea`.

## Repository/source boundaries at pause

### Harness and evidence

Path: `~/vibe-coding-projects/coding/lg-v30-port/`

- branch: `master`;
- pre-handoff HEAD: `2c4dec2aef2fcd00e513131d83f48566b0d2db34`;
- upstream relation before this handoff: seven commits ahead of
  `ghpub/master`;
- tracked worktree/index: clean before creating this handoff;
- this handoff is the sole intended tracked change/commit in the preservation
  step;
- no push is authorized.

Git-ignored `out/` is about 2.71 GB across 622 files and will not survive a
normal clone. It must be restored from the private migration checkpoint.

Pre-existing untracked material, deliberately not Git-added:

- `docs/reconstructed-handoff-2026-07-19-k097-k101-moa.md`;
- `firmware/zap/a540_*` proprietary firmware;
- `initramfs/root/lib/firmware/qcom/a530_*` and `a540_*` firmware.

These are preserved in a separately labelled private supplemental archive.
Their presence is not permission to publish them.

### Mainline kernel

Path: `~/vibe-coding-projects/coding/linux-mainline-v30/`

- branch: `joan/latest-clean-test`;
- HEAD: `16e3950bf9135070bd042ffc84e50e6ca7ebf468`;
- worktree/index: clean;
- repository is shallow;
- `.config` SHA-256:
  `b071ec63d1ef4f1ab0e5691847ce577d5512686868d2f876828f93df6ff8a49f`.

The detached worktree
`~/vibe-coding-projects/coding/<historical-test-worktree>/` is clean at
`6c5f06bc80b3d0ffacf3d5924178977eccf6f56a`. That commit is reachable from
preserved local refs in the primary kernel repository, so a separate 2.3 GB
worktree copy is not required. Its separate `.config` is preserved with the
worktree-state report.

Do not pull or merge the same-named remote touch/GPU lineage into the clean
local checkpoint.

### pmaports

Path: `~/.local/var/pmbootstrap/cache_git/pmaports/`

- branch: `device-lge-joan`;
- HEAD: `25f24b1d2608bbba6b49df165a6034b1dfc7b37d`;
- worktree/index: clean.

The migration checkpoint preserves the repository, redacted pmbootstrap config,
pmbootstrap log, and the four current joan APK artifacts. Chroots and general
pmbootstrap caches are intentionally excluded; do not invoke pmbootstrap to
recreate them until work is explicitly resumed.

### Downstream reference

Path: `~/vibe-coding-projects/coding/android_kernel_lge_msm8998/`

- branch: `lineage-22.2`;
- HEAD: `c022ed57679b432bff277eaca0a2366a72218925`;
- worktree/index: clean;
- shallow, reference-only; never build or modify.

## K104 status

K104 has not been prepared, built, or run. No K104 artifact exists.

If Lance later explicitly resumes, K104 is instrumentation-only. Capture, in
order:

1. regulator-enable and reset-GPIO stages;
2. each STMFTS command byte and I2C return;
3. completion-wait entry and exit;
4. IRQ-handler entry;
5. raw event bytes.

Do not combine a protocol adaptation, IRQ change, and DT change in one test.

## Safety

- Never boot quarantined K101
  (`494a7cfaf2e5fc2e9439718f7845f90a4956bed4cac68b114dc2cbeb0470a34c`).
- Do not run the current `scripts/tethered-test.sh`; its active fastboot command
  still uses a host timeout.
- Never wrap an active LG fastboot client in `timeout` or another deadline that
  can kill it mid-transfer.
- Never automatically retry fastboot after incomplete or ambiguous transport.
- Do not use `fastboot getvar` on this LG bootloader.
- No device-facing command is authorized by this handoff.

## Memory continuity

Hermes-native compact memory contains the pause/no-auto-resume rule and was
read back after writing. The local shared-memory workspace also contains the
shared pause conclusion for peers `human maintainer` and `Hermes Agent`; several
equivalent duplicate observations may exist because transient failed responses
were later found to have committed. They are harmless and were not deleted.

The portable checkpoint includes a redacted project-memory snapshot and the
current `mobile-linux-hardware-bringup` skill directory. Full Hermes/OpenClaw
and Honcho runtime/database migration is outside this LG V30 project checkpoint
and must follow the broader agent-runtime migration plan.

## Private off-host migration checkpoint

Expected final path:

`private backup mount: migration checkpoints/lg-v30-k103-pause-20260721T180143Z/`

The expected filesystem UUID is
`acda89be-6e20-4b35-975a-2a4028cf4aee`. The checkpoint must be staged under a
unique `.partial` directory with mode `0700`, verified, synced, and then
atomically renamed. Treat all checkpoint content as private. The old host stays
untouched and authoritative for rollback until the faster host restores and
verifies every component.

Planned checkpoint contents:

- Git bundles and shallow-repository mirrors for harness, kernel, pmaports, and
  downstream reference;
- complete private `lg-v30-port/out/` archive;
- restricted supplemental archive for pre-existing untracked handoff/firmware;
- canonical and detached-worktree kernel configs;
- redacted pmbootstrap state plus joan APKs;
- current mobile-Linux skill archive;
- redacted memory/config/state reports;
- exact restore instructions;
- top-level SHA-256 manifest and verification transcript.

The checkpoint manifest intentionally records the final harness bundle tip,
which is the signed local commit containing this handoff. Its detached hash is
recorded outside Git in the checkpoint result and durable memory to avoid a
self-referential commit/manifest cycle.

## Secrets and identities that require separate secure migration

The project checkpoint does **not** copy these raw values or private keys:

- `~/.android/adbkey*` — required to preserve existing ADB authorization;
- `~/.ssh/<device-ssh-key>*`;
- `~/.ssh/<github-signing-key>*`;
- `~/.hermes/secrets/` and `~/.hermes/.env`;
- GitHub authentication stores;
- Nextcloud credentials/TOTP material;
- Honcho/Postgres, OpenClaw agent runtime, and Hermes runtime databases/configuration
  handled by the broader system migration.

All values are `[REDACTED]`. Migrate these through the dedicated secure secrets
and stateful-service path, not by adding them to this project archive.

## Restore order on the faster host

1. Keep the old host online but quiescent as rollback.
2. Mount/copy the private checkpoint and verify its top-level `SHA256SUMS`.
3. Verify every Git bundle and mirror archive before restoring worktrees.
4. Restore the harness bundle first and confirm its signed local tip contains
   this handoff; do not merge/pull remote history.
5. Restore the kernel and pmaports repositories, branches, refs, and configs;
   confirm exact HEAD/config hashes before any build.
6. Restore `lg-v30-port/out/` and verify the sealed K103 46-entry manifest plus
   active K103 and K101 quarantine hashes.
7. Restore the restricted supplemental firmware/handoff archive without
   Git-adding it.
8. Restore redacted pmbootstrap state/APKs; recreate chroots only after explicit
   resume authorization.
9. Restore the mobile-Linux skill and the broader Hermes/Honcho/OpenClaw state
   through their own migration procedure.
10. Migrate private keys/secrets separately; verify permissions and ADB/Git
    identities without printing values.
11. Re-run repository, bundle, manifest, and memory readback checks.
12. Stop. Do not build or access the phone until Lance explicitly resumes.

## Toolchain snapshot

- `aarch64-linux-gnu-gcc 16.1.0`;
- GNU Make `4.4.1`;
- DTC `1.7.2-2-gc28d0cf`;
- Zstandard `1.5.7`;
- Git `2.55.0`;
- Python `3.14.6`.

No package was installed for this checkpoint. `age` was unavailable, so the
checkpoint is protected by the trusted off-host filesystem plus restrictive
Unix modes rather than a new ad-hoc encryption key. Treat the external disk
and checkpoint as private; do not upload or publish it.

## Attribution boundary

K103 execution provenance was `moa/oops-all-chatgpt-all-max` with acting model
`openai-codex:gpt-5.6-sol[reasoning=max]` and two same-route references. No
async delegation contributed to K103. The earlier timed-out delegation batch
had unknown child model provenance and supplied no final findings.

This preservation task uses the same MoA preset/acting route shown at the top
of this handoff. No additional delegation was launched.
