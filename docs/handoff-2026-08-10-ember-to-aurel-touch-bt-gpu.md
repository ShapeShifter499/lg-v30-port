# Handoff to Aurel — 2026-08-10: BT and the keypad are both fixed

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-10

Both of the lanes you handed me are closed and device-proven. Two of your
conclusions turned out to be wrong, and I want to be straight about which
and why — in both cases your reasoning was sound for the evidence you had.

## 1. Bluetooth — CLOSED, autostart proven

**hci0 was never broken.** It was registered, setup-complete, and parked
as `HCI_UNCONFIGURED`, missing exactly one thing. The mgmt interface says
so directly:

	READ_INDEX_LIST          count=0  -> (none)
	READ_UNCONF_INDEX_LIST   count=1  -> hci0
	READ_CONFIG_INFO hci0    missing=0x2 [PUBLIC_ADDRESS]

bluetoothd does not expose unconfigured controllers as adapters, which is
why Settings said "no controller" while rfkill was happy. Phosh's icon lit
because an mgmt index existed.

**Cause: our own commit `240de5d2f`.** It sets
`HCI_QUIRK_USE_BDADDR_PROPERTY` unconditionally.
`hci_dev_setup_sync()` folds that quirk into `invalid_bdaddr` and only
clears it once an address is found *and* applied, so with the property
gone the controller is forced unconfigured. It regressed the moment the
test `local-bd-address` came out of the DTS — which was the right call on
your part, a per-device MAC cannot ship.

Confirmed four ways, the cleanest being: `boot-joan-bt-bdaddr.img` is the
*only* staged image containing the string `local-bd-address`.

### Two corrections

- **`-84` is `-EILSEQ`, not `-EPROTO`, and it is a red herring.** The
  version read succeeds 150 ms after it, the firmware download ACKs every
  chunk, and it reappears on boots where BT comes up perfectly.
- **Mainline never sets that quirk for QCA.** Before `240de5d2f` the only
  QCA quirk was `HCI_QUIRK_BDADDR_PROPERTY_BROKEN` (a byte-order flag). As
  written the commit would strand every in-tree QCA board that carries a
  usable NVM address, so it needed a gate regardless of joan.

### joan has no factory BT MAC — and neither does Android

Worth writing down so nobody hunts for it again. The NVM address TLV
(`crnv21.bin`, tag 2, len 6) is all zeroes. LG's `btnvtool` contains
`Writing Random BD_ADDR` and `/persist/bluetooth/.bt_nv.bin`; that
directory does not exist, verified with root on LineageOS at the real
mount point `/mnt/vendor/persist`. The address LineageOS actually uses,
`22:22:4E:0B:DB:01`, lives in `/data/misc/bluedroid/bt_config.conf` — the
stack's own cache. A binary search for those six bytes across modemst1,
modemst2, fsg, fsc and persist returns **zero hits**.

So Android generates a random locally-administered address once and keeps
it in `/data`. Wipe userdata and the phone gets a different BT MAC. Your
`22:22:...` was not a hand-picked test value — it is the device's real
LineageOS address, and I mischaracterised it earlier; sorry.

We ship a *derived* address instead: `02:00:A0:AC:61:B0` from the fused
SoC serial `0xA0AC61B0`. Stable, unique, needs no storage, and is more
reproducible than Android's. Trade-off: it differs from LineageOS's, so
pairings do not carry across.

### Fix

- kernel: gate the quirk on the property being present + an all-zero
  `local-bd-address` placeholder in joan's DTS (as `qcs404-evb.dtsi` does)
- device: `/usr/local/sbin/joan-bt-address` + openrc service, deriving the
  address from the SoC serial and applying it over the mgmt socket. It
  speaks mgmt directly because joan has no route off the USB link, so
  `apk` cannot reach the mirrors — no package needed, python3 is there.

Proven across two boots with no manual step: `joan-bt-address [started]`,
`Controller 02:00:A0:AC:61:B0 LG V30 [default]`, discovery returns 16
devices with live RSSI.

**Two traps that will bite anything you install on that rootfs:**

1. `need dev` is unsatisfiable on pmOS (no `/etc/init.d/dev`; it uses
   devfs/udev). OpenRC then refuses the service *and* hides it from
   `rc-status`, so it looks like it was never enabled.
2. The clock runs **backwards** through boot — `rtc-pm8xxx` sets it to
   1970 at ~15.7 s — so files installed afterwards carry 1970 mtimes.
   OpenRC stamps `/run/openrc/deptree` with the newest init-script mtime
   it scanned and only rebuilds when something looks newer. A 1970 file
   never does. Use `touch -d "<real date>"` on anything you install.

## 2. The keypad freeze — CLOSED, and it was not the compositor

Your instinct that the kernel/input layer looked clean was based on events
*existing*. They existed but were malformed.

`stmfts` assumes every contact it opens is eventually closed. The
controller opens contacts it never mentions again, so the slot stays
occupied for the life of the input device. The decisive measurement —
`EVIOCGMTSLOTS`, with nothing touching the screen:

	slot 0: 622   slot 1: 624   slot 2: 637   slot 4: 632   slot 5: 636
	PHANTOM CONTACTS HELD RIGHT NOW: 5

Every real tap therefore arrived as a *sixth* contact, i.e. a multi-touch
gesture rather than a press. phosh routed them to its lockscreen
brightness gesture — Lance independently reported the brightness OSD
flashing while tapping — so no button ever saw a press. Swipes kept
working because gestures are deltas. phoc said the same from its side:
`Touch point N already tracked, ignoring`.

**The phantoms are display noise, not fingers.** Decoded, they sit at
x=27 and x=56 of 1440 — hard against the left edge — and appear as the
panel powers up.

### Fix: `INPUT_MT_DROP_UNUSED`

The driver already called `input_mt_sync_frame()`; it just was not allowed
to act on it. Safe here because measurement says so:

- a finger held motionless is re-reported at **~125 Hz** (249 interrupts
  per 2 s, steady) so it is in every frame and cannot be dropped
- a stranded contact is **silent** — two slots occupied, zero interrupts
  across ten seconds

I nearly ported your vendor-style approach (`touch_count` + per-finger
state + `fts_release_all_finger()` on any inconsistency, as `ftm4_ts.c`
does). Lance asked whether mainline had prior art, and it does: 26 in-tree
drivers use `INPUT_MT_DROP_UNUSED` and **none** keep a defensive counter.
The one-liner was the better answer and that question is what found it.

Verified over taps, a held drag and three lock/wake cycles: worst slots
held = 1 (the real finger), zero at rest, and all three phoc touch error
counters at zero.

### Theories the data killed

So you do not re-run them: my own "stuck contact" retraction (right in
substance, retracted on a bad measurement); phoc rejecting touches (those
`Touch event ignored` lines only fire during genuine screen-off); scale
mismatch (phoc and phosh both report scale 3.0 / logical 480x960, your
Aug-8 dead-zone config is not live); and slot-ID decode (raw packets show
`03`/`04` with slot 0 for one finger — `(event[0] & 0xf0) >> 4` was always
correct). The fingerprint sensor is also ruled out: no FP node in joan's
DT, touchscreen alone on `blsp1_i2c5`, no SPI device bound.

## 3. Your GDSC workaround — reverted, and it was a no-op

`531e7b10e` (A540 `inactive_period` 250 ms -> 300000 ms) was added because
of "a frozen lockscreen keypad whose taps land inside the stall window."
That diagnosis is now disproven, so I reverted it to upstream's 250 ms.

But I owe you a correction here too. I first claimed it was costing
battery, quoting your own "battery cost real". Measured at **both**
values, the GPU power domain never suspends at all:

	inactive_period = 300000:  runtime_suspended_ms = 0  (whole boot)
	inactive_period = 250:     runtime_suspended_ms = 0  before AND after
	                           65 s with the screen OFF

So it was **harmless and useless**, not a battery sink — and it could not
have helped wake latency either, since the domain it was holding up was
never collapsing. My "battery cost" line repeated your prediction without
testing it.

**New lane, filed as Deck card 94:** something pins the GPU's runtime PM
reference permanently. Userspace is innocent — phosh drops to 0% CPU with
the screen off. The GPU parks at its minimum 257 MHz and stays active
anyway. Next step is `CONFIG_PM_ADVANCED_DEBUG` to expose
`power/runtime_usage`, then hunt the unbalanced `pm_runtime_get` in
drm/msm. A domain that never collapses on an idle phone is a real standby
drain.

Separately: the lockscreen's low frame rate is your GTK3 Cairo finding
(phosh at 79% CPU with the screen on), already decided as "live with it
till GTK4". Not a regression, not related to the GDSC value.

## 4. Deck card 86 was 14.95 MB

The block starting `## SESSION STATE 2026-08-09 LATE` appeared **4096
times** — a 2^12 doubling ladder, the signature of a read-modify-write
append that got retried. They were **not** identical: 13 distinct
variants, so a blind "keep one copy" would have destroyed ~420 unique
lines. I removed only exact duplicates: 14.95 MB -> 64.9 KB, unique
non-empty lines 634 before and 634 after, all 33 of your attribution
blocks intact. Original preserved at
`~/.ember/workspace/card86-backup-20260810-original.json` on nym-skyforge.

Prevention: use card **comments** for session updates (append-only, so a
retry costs a duplicate comment rather than a doubled card). Endpoint is
`POST /ocs/v2.php/apps/deck/api/v1.0/cards/<id>/comments` — the
`/index.php/...` path returns 405 — and comments cap at **1000
characters**, so long material goes in `Shared_AI_agents_files/handoffs/`
with a pointer comment.

## 5. Repo state

PRs #7 and #5 are **parked, untouched**. Nothing has been pushed.

`240de5d2f` as it stands in PR #7 still contains the ungated quirk — it
would strand every QCA controller. Do not merge that PR as-is; the
corrected version lives on the new branches.

Local branches on nym-skyforge, `/tmp/joan-bt-fix`:

- **`ember/joan-touch-fixes`** — 3 commits on `joan/latest-clean-test`,
  applies cleanly, compiles. Ready to push as the touch PR.
- **`ember/joan-fixes-v2`** — 6 commits (BT + touch) on `9bfc50add`,
  verified byte-identical to the device-tested kernel apart from removing
  the dead `drm_atomic` debug prints.
- **`ember/joan-integration-v2`** — the reconciliation onto
  `latest-clean-test`, **incomplete**: touchscreen (3) + battery (8) +
  modem (3 of 5) = 14 commits. Stopped cleanly, no half-applied state.

Still to do on the integration branch:

1. `d38242fb5` (enable the modem) conflicts because it originally sat
   *before* the gnoc/IPA work; re-order it ahead of `8aab25b4b`.
2. Split `68b940416` into a BT-node commit and a WiFi-enable commit
   (Lance approved this) so BT and WiFi land in separate groups.
3. Then: BT group (split-BT, `569fbe2c7`, UART/NVM, BD address, DTS
   placeholder) and finally the WiFi enable as "initial work".

Note `latest-clean-test` is *behind* the integration branch — it has no
Bluetooth DT node and none of the modem chain — so it is not yet a
superset of what runs on the device. That is what this reconciliation is
for.

## 6. Method notes

- **Read device state, do not infer it.** `EVIOCGMTSLOTS` answered in one
  call what an hour of event-stream reasoning got wrong. I retracted a
  correct diagnosis because one stream sample showed zero contacts.
- **The vendor kernel is ground truth.** `getevent` under LineageOS showed
  a clean single-finger tap on one slot with paired down/up, which proved
  the fault was ours and not the hardware.
- **Check `uname -r` against the expected commit after every boot.** One
  `fastboot boot` silently no-op'd because the phone was in pmOS and
  `adb reboot bootloader` had nothing to talk to.
- **Don't double-background a build.** `nohup make &` inside a backgrounded
  call reports the wrapper shell's exit, not the build's; I read sizes off
  two-hour-old artifacts and called a build clean.
- **busybox `grep` has no `--line-buffered`** — a watch built on it dies
  instantly and looks exactly like "no events occurred".

Your UART clock work and the BD-address idea were both right. The commit
just needed a gate, and the keypad needed a measurement rather than a
theory.
