# Handoff: joan bench — night of 2026-09-11/12 (Fulgor → next session)

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: ZCode:zai-coding-plan/GLM-5.3
Date: 2026-09-12 (written at end of the 09-11 night bench)

STANDING APPROVAL (Lance): always look at the code and reverse engineer
stock ROM/kernel wherever it helps the port — state this in every joan
handoff and note. Standing goal: the port should FEEL like the software
was made for the device.

## Phone state at handoff

US998, SD-card pmOS, booted from the v3.1 RAM image (fastboot boot):
- kernel 7.2.0-rc2 (r14 = tip 2b6ecf829cd7, ESP modules + PM_DEBUG in
  config), full cmdline VERIFIED live (q6core.skip_versions=1,
  ipa.lowmem=1, systemd.mask=usb-signaller.service).
- Sound card UP: `[LGV30] sdm845`. r14 kernel+device apks INSTALLED on the
  rootfs (modules consistent); USB profile swapped to
  default-profile-developer; input-boost + lock-scale daemons installed.
- MBHC: **0 MBHC virqs this boot** — the boot lottery (below). Last clean
  boot had all 7 MBHC handlers registered + impedance controls.

## The validated win: jack-detect patches WORK on a clean boot

On one v3.1 boot the interrupt controller fully came alive: parent
wcd934x_irq (msmgpio 54) fired 66× and demuxed 66 events to the slim
child; **all seven MBHC handlers registered** ("mbhc sw intr", "Button
Press/Release detect", "Elect Insert/Remove", "HPH_L/R OCP detect") and
the impedance controls existed = `wcd_mbhc_init()` succeeded. The
one-fire-then-silence disease from the pre-fix kernels is gone.

**Follow-up fix needed (small)**: the probe-time LEVEL init
(abc48a756b0f) is overwritten — regmap-irq's set_type rewrites each
LEVEL byte per-irq at request time and last-writer-wins, so LEVEL0
reads 00 not 01. The correct home for it is the type table itself:
give WCD934X_IRQ_SLIMBUS (entry 0) `types_supported |= LEVEL_HIGH` with
`type_level_high_val = BIT(0)` in the WCD934X_REGMAP_IRQ_REG macro
args, matching downstream's `irq_level_high[0] = true`. Empirically the
controller works even at 00 (slim traffic is pulse-tolerant), so this
is correctness, not a blocker.

## The open problem: boot lottery

Two v3.1 boots, two outcomes:
- **Boot A (clean)**: everything above; reached login.
- **Boot B (wedged)**: codec half-probed (slimbus devices enumerated,
  codec controls exist), MBHC never armed, **Phosh spinner forever**
  (system degrades under load; the 300 s phosh timeout recovers ssh but
  not phosh).
Prime suspect: the soundwire specifier fix (joan DTS `interrupts-extended
= <&wcd9340 8>`) — it opened the never-before-executed swm probe path,
and the WSA soundwire child can hang waiting for the codec's soundwire
segment. **Bisect**: build with the LEVEL fix moved into the type table
AND the specifier reverted to 20; if wedging stops, harden the swm probe
(defer/handle-missing-slaves) instead of reverting. N=2 so far.

## Boot recipe (flaky USB — fire immediately)

The bench USB re-enumerates; every failed `fastboot boot` died when the
session sat idle. Working pattern: LOS up → **immediately**
`adb reboot bootloader; sleep 10; sudo -n fastboot boot <img>` in one
command chain. If the send fails with "Write to device failed", the
image may STILL boot (the phone had the bytes before the flush error —
happened twice). Recover from dark states: force-off (power ~10 s) →
normal power-on → LOS → adb → chain again.

Image: nest `~/joan-test-assets/jack-cellular-20260911/
boot-joan-pmos-r14-jack-cellular-20260911.img` (sha256 0c99c321…,
cmdline = label args + mask + skip_versions + slim_dbg + ipa.lowmem).
Kernel/device r14 apks + joan-modules-r14.tgz alongside. The r14 apks
are ALREADY installed on the SD rootfs — a new boot needs no apk work.

## What the bench proved tonight

- r14 kernel boots and drives the full stack: card, display, touch
  (module/kernel consistency verified by md5).
- Audio bring-up needs the FULL deviceinfo cmdline (skip_versions!) —
  the first v3.1 image without it had no ADSP → no slimbus → no codec.
  v3.1 has it; any future image must too (as must any laf flash: the laf
  boot without ipa.lowmem shows the IPA GSI channel timeout Lance saw —
  "GSI command 2 for channel 5 timed out" — expected, workaround domain).
- developer-default USB profile WORKS on both kernels (rootfs-level
  config): the gadget survives reboots, signaller flip becomes
  reconfigure-with-network. umtprd (MTP) rides along.
- Access quirks: nest-side `sudo ip link/addr` REQUIRED (silent failures
  otherwise); phone has no scp — pipe via `cat | ssh 'cat > file'`;
  ship phone scripts as files (no nested-quote commands, no evtest —
  python3 stdlib reads /dev/input); `sshpass -p 147147 ssh
  user@172.16.42.1` from the nest; laf = download mode AND the pmOS
  boot target (Vol-Up+plug); abl fastboot = `adb reboot bootloader`
  (or Vol-Down+plug); laf boots = r5 kernel without ipa.lowmem → IPA
  GSI timeouts expected.

## Phase 1 (headset) — resume exactly here

1. Boot v3.1 (recipe above), wait for ssh (~90 s), verify:
   `grep -cE "sw intr|OCP|Press" /proc/interrupts` — if ≥4, MBHC armed
   (boot-lottery winner); if 0, reboot once (lottery) or bisect (§ above).
2. Arm watcher: /tmp/jw2.py (python3, reads /dev/input/input4, writes
   /tmp/jack2.txt) + irq log — recreate from this handoff if /tmp lost.
3. Lance: plug/unplug the headset (one-button remote: expect
   KEY_PLAYPAUSE band), press the button ×3, unplug.
4. Pull /tmp/jack2.txt + /proc/interrupts deltas. Events firing = the
   jack-detect program is DONE; then in-line mic capture (Headset UCM
   device, sticky-TX reset rule first) and button keycode verification.
5. If events fire but keycode is wrong → threshold ladder diagnosis;
   if no events with LEVEL confirmed → MBHC floor/bias register dump
   (downstream parity per docs/2026-09-11-wcd934x-irq-re-map.md).

## Phase 2 — cellular (ready to start after Phase 1)

ESP modules are IN the r14 kernel. M0 = joan-imsd first-boot ISIM read +
`joan-ims register` live on T-Mobile (all ingredients proven
2026-08-26); M1 = MT fixes (stable GUA, P-CSCF keepalives, TCP-in-xfrm);
M2 = RTP↔PipeWire bridge + AGC. Full plan:
docs/2026-09-11-ims-calls-pmos-report.md. Phase 3 suspend ladder:
pm_test available (PM_DEBUG=y), start at `devices` level; the decisive
TZ SYSTEM_SUSPEND probe + fallback design in
docs/2026-09-11-suspend-resume-report.md.

## Repo/artifact state (all pushed)

- kernel `joan/latest-clean-test` = `joan/wake-path-v1` = `2b6ecf829cd7`
  (jack patches + es9218p LPB + everything prior). master frozen at
  ab54ef66 (Lance to decide retirement per upstreaming report).
- pmaports `joan/readme-build-guide` @ 18655bc827 (+ fakeroot-mkdir fix):
  kernel pkgrel 14 pinned 2b6ecf829cd7, ESP+PM_DEBUG config, device
  pkgrel 14 (developer-default dep + input-boost + lock-scale).
- lg-v30-port @ adfd19a: six investigation reports + order-of-operations
  + this handoff. All reports carry the standing RE approval.
- USB/USB-C: docs/2026-09-11-usb-gadget-and-usbc-report.md (permanent fix
  shipped; USB-C map: PD on PMI8998, SBU mux GPIOs 11/16/90, BOB VBUS;
  DP alt-mode = last/hardest; host milestone = USB stick via BOB vbus +
  usb-role-switch DT).
- Investigations ALL complete: perf, fingerprint (FPC1022), IMS/calls,
  camera (CAMSS in-tree at 4dd87de5e58d, DT node = gate), suspend,
  upstreaming (first PR = wcd934x slimbus init fix to Brown — Lance to
  approve the draft).

## Lance's decision list

1. UFS rootfs vs SD-only (biggest perf win; UFS fully probes).
2. Retire/divergent `master` handling (upstreaming report §0).
3. GND_DET_EN experiment promotion (parked on its own branch).
4. `joan/master-proven-fixes` 50/11 reconciliation (separate session).
5. Redundant branch deletions (joan/audio-lpb-*).
6. wcd934x first-PR draft for review.
7. Headset with 4-button remote for the full threshold-ladder test.

## House rules

Trailers `Signed-off-by: Lance <Gero3977@gmail.com>` +
`Assisted-by: <harness>:<model>`; never `Co-Authored-By: Claude`.
Stage-then-push with Lance's explicit OK per target (kernel
latest-clean-test + pmaports + lg-v30-port pushes are currently
pre-approved flow). SD-card path only for now. Never flash during
qualification. Never point IPA DMA at guessed addresses.
