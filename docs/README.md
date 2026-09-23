# docs/ index

Every document in this directory, grouped by what it is for. File names are
kept as they were published, because closure packets and tracker entries
link to them by path. Inside a topic, newest is first.

Names carry a date. Some also carry the name of a local agent persona
(`ember-*`, `aurel-*`); that is the author label from when the doc was
written. See the attribution policy in [PROVENANCE.md](../PROVENANCE.md).

## Start here

- [status-history.md](status-history.md) — dated status snapshots that used
  to live in the README (2026-07-04 .. 2026-08-03).
- [test-results/README.md](test-results/README.md) — **mandatory** device-test
  index and closure-packet rules.
- [kernel-change-ledger.md](kernel-change-ledger.md) — every kernel change,
  with evidence and status.
- [project-history-and-attribution.md](project-history-and-attribution.md) —
  who did what, when.
- [joan-firmware-and-package-requirements.md](joan-firmware-and-package-requirements.md)
  — firmware to extract from your own phone, packages, kernel config.
- [device-session-setup.md](device-session-setup.md) — getting a working
  Phosh session on postmarketOS.
- [recon-2026-07-04.md](recon-2026-07-04.md) — original background.

## Latest handoffs (2026-08-10)

- [ember-handoff-2026-08-10-session-close.md](ember-handoff-2026-08-10-session-close.md)
  — **current state**: BT, keypad, rainbow and power-key lanes closed; the
  open lanes listed.
- [ember-2026-08-10-unpin-result-was-confounded.md](ember-2026-08-10-unpin-result-was-confounded.md)
  and [ember-handoff-2026-08-10-for-aurel-card94-retest.md](ember-handoff-2026-08-10-for-aurel-card94-retest.md)
  — A540 runtime-PM retest, staged but not yet booted. The uncommitted kernel
  change is saved as
  [20260810-ember-a5xx-icc-drop-on-suspend-plus-unpin.patch](20260810-ember-a5xx-icc-drop-on-suspend-plus-unpin.patch).
- [ember-2026-08-10-rainbow-on-wake-was-brightness.md](ember-2026-08-10-rainbow-on-wake-was-brightness.md)
- [ember-handoff-2026-08-10-touch-phantom-contacts.md](ember-handoff-2026-08-10-touch-phantom-contacts.md)
- [ember-handoff-2026-08-10-branch-convention-corrected.md](ember-handoff-2026-08-10-branch-convention-corrected.md)
  — `master` = verified fixes, `joan/latest-clean-test` = raw history.
- [ember-note-2026-08-10-for-aurel-paths-and-ccache.md](ember-note-2026-08-10-for-aurel-paths-and-ccache.md)
  — master boot verified; build layout, ccache, `olddefconfig` trap.
- [aurel-handoff-2026-08-10-integration-v3-complete.md](aurel-handoff-2026-08-10-integration-v3-complete.md),
  [handoff-2026-08-10-aurel-to-ember-integration-landed.md](handoff-2026-08-10-aurel-to-ember-integration-landed.md),
  [handoff-2026-08-10-aurel-to-ember-followup-pruning.md](handoff-2026-08-10-aurel-to-ember-followup-pruning.md),
  [handoff-2026-08-10-ember-to-aurel-touch-bt-gpu.md](handoff-2026-08-10-ember-to-aurel-touch-bt-gpu.md)
  — the integration and branch work behind the above.

## Kernel configs

- [master-47041183b.config](master-47041183b.config) — known-good config for
  `master` (fuel gauge enabled). Start builds from this one.
- [integration-20260808.config](integration-20260808.config) — the
  2026-08-08 integration build.

## By subsystem

**Bluetooth / Wi-Fi**
[ember-handoff-2026-08-09-bt-unconfigured-root-cause.md](ember-handoff-2026-08-09-bt-unconfigured-root-cause.md),
[ember-handoff-2026-08-09-to-aurel.md](ember-handoff-2026-08-09-to-aurel.md),
[aurel-handoff-2026-08-09-bt-alive-touch-compositor.md](aurel-handoff-2026-08-09-bt-alive-touch-compositor.md),
[aurel-handoff-2026-08-09-to-ember-touch-fixed.md](aurel-handoff-2026-08-09-to-ember-touch-fixed.md),
[aurel-handoff-2026-08-08-wifi-bt-to-ember.md](aurel-handoff-2026-08-08-wifi-bt-to-ember.md).

**Modem**
[ember-handoff-2026-08-08-modem-layer1-and-integration.md](ember-handoff-2026-08-08-modem-layer1-and-integration.md).

**Interconnect / QoS**
[ember-handoff-2026-08-07-bimc-qos-closed.md](ember-handoff-2026-08-07-bimc-qos-closed.md),
[upstream-question-icc-rpm-qos-clocks.md](upstream-question-icc-rpm-qos-clocks.md),
[test-results/mas-ipa-2026-08-07.md](test-results/mas-ipa-2026-08-07.md).

**Battery / PMIC**
[pmi8998-fg-rfc-test-report-2026-08-07.md](pmi8998-fg-rfc-test-report-2026-08-07.md),
[battery-bringup-audit-2026-08-07.md](battery-bringup-audit-2026-08-07.md).

**Display / panel (SW43402, DSI, DSC)**
[panel-sw43402.md](panel-sw43402.md) (parcel P2),
[display-path.md](display-path.md) (parcel P3),
[dsi-comparison-mainline-vs-downstream.md](dsi-comparison-mainline-vs-downstream.md),
[d1-dsi-link-rate-fix.md](d1-dsi-link-rate-fix.md),
[aurel-handoff-2026-08-07-d-series-closed.md](aurel-handoff-2026-08-07-d-series-closed.md),
[handoff-2026-07-28-slider-serialisation.md](handoff-2026-07-28-slider-serialisation.md),
[handoff-2026-07-19-night2-dsi-ctrl-session1.md](handoff-2026-07-19-night2-dsi-ctrl-session1.md),
[handoff-2026-07-19-first-light-k088.md](handoff-2026-07-19-first-light-k088.md),
[reconstructed-handoff-2026-07-19-k097-k101-moa.md](reconstructed-handoff-2026-07-19-k097-k101-moa.md),
[handoff-2026-07-11-k078-k079-display-two-paths.md](handoff-2026-07-11-k078-k079-display-two-paths.md),
[handoff-2026-07-11-k076-k077-display.md](handoff-2026-07-11-k076-k077-display.md),
[handoff-2026-07-11-k074-clock-divider.md](handoff-2026-07-11-k074-clock-divider.md),
[handoff-2026-07-11-k068-k071-display.md](handoff-2026-07-11-k068-k071-display.md),
[handoff-2026-07-11-m4-display-next.md](handoff-2026-07-11-m4-display-next.md),
[handoff-2026-07-11-m4-smmu-next.md](handoff-2026-07-11-m4-smmu-next.md).
Downstream reference copies (GPL-2.0): [downstream-refs/](downstream-refs/README.md).

**GPU (Adreno 540)**
[handoff-2026-07-27-gpu-rendering-works.md](handoff-2026-07-27-gpu-rendering-works.md),
[handoff-2026-07-26-gpu-submit-path.md](handoff-2026-07-26-gpu-submit-path.md),
test packets `GPU-FULL3`, `G4`, `G5-OC*`, `G6-OC3` in [test-results/](test-results/README.md).

**Touch**
[handoff-2026-07-21-k103-input-enable-discriminator.md](handoff-2026-07-21-k103-input-enable-discriminator.md),
[handoff-2026-07-21-hardware-migration-pause-after-k103.md](handoff-2026-07-21-hardware-migration-pause-after-k103.md),
[handoff-2026-07-20-k102-touch-and-clean-regression.md](handoff-2026-07-20-k102-touch-and-clean-regression.md).

**CPU clocks**
[c2-osm-cpu-clock-port.md](c2-osm-cpu-clock-port.md).

**Storage / SD card**
[sd-card-fsck-and-recovery.md](sd-card-fsck-and-recovery.md).

**postmarketOS bring-up**
[handoff-2026-07-11-pmos-firstboot.md](handoff-2026-07-11-pmos-firstboot.md),
[handoff-2026-07-10-milestone1-pmos-plan.md](handoff-2026-07-10-milestone1-pmos-plan.md).

## Early reset hunt (2026-07-04 .. 07-10, historical)

[handoff-2026-07-10-pstore-tlmm-k050.md](handoff-2026-07-10-pstore-tlmm-k050.md),
[observability-tlmm-gpio-2026-07-08.md](observability-tlmm-gpio-2026-07-08.md),
[post-reset-observability-plan-2026-07-08.md](post-reset-observability-plan-2026-07-08.md),
[handoff-2026-07-08-mm-noc-current.md](handoff-2026-07-08-mm-noc-current.md),
[handoff-paste-2026-07-08.md](handoff-paste-2026-07-08.md),
[handoff-2026-07-07-k029-onion-peel.md](handoff-2026-07-07-k029-onion-peel.md),
[k028-conf-noc-sweep-hypothesis-2026-07-07.md](k028-conf-noc-sweep-hypothesis-2026-07-07.md),
[handoff-2026-07-07-k027-complete.md](handoff-2026-07-07-k027-complete.md) (device safety contract),
[handoff-2026-07-06-session2.md](handoff-2026-07-06-session2.md),
[handoff-2026-07-06.md](handoff-2026-07-06.md),
[2026-07-06_lg-v30-reset-cause-PS_HOLD.md](2026-07-06_lg-v30-reset-cause-PS_HOLD.md),
[imem-oracle-result-2026-07-06.md](imem-oracle-result-2026-07-06.md),
[imem-oracle-run.md](imem-oracle-run.md),
[nullinit-discriminator-run.md](nullinit-discriminator-run.md),
[bringup-debug-state-2026-07-06.md](bringup-debug-state-2026-07-06.md),
raw captures [downstream-diag-2026-07-06.txt](downstream-diag-2026-07-06.txt),
[pmic-pon-pass-2026-07-06.txt](pmic-pon-pass-2026-07-06.txt).

## Process

- [public-upstreaming-plan.md](public-upstreaming-plan.md) — what a PR-ready
  kernel change must carry.
- [dependency-tracker.md](dependency-tracker.md) — host packages and
  sources pulled in.
- [templates/candidate-test-closure.md](templates/candidate-test-closure.md)
  — closure-packet template.

Most docs cite evidence under `out/` (logs, images, patches). That directory
is local to the original maintainers' host and is not published; the docs
record each artifact's hash so it can be matched if it is shared later.

Assisted-by: Claude-Code
Date: 2026-09-23
Update-scope: New index.
