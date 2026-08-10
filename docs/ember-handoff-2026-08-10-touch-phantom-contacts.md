# Handoff: the lockscreen keypad was phantom MT contacts — 2026-08-10

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-10

The keypad freeze is fixed, device-verified, and the cause was not what
any of us thought. It was never the compositor, never a GPU resume stall,
and never a scale mismatch.

## What was wrong

`stmfts` assumed every contact it opens is eventually closed by a matching
leave event. The controller does not honour that. Contacts get opened and
never mentioned again, and the slot stays occupied for the lifetime of the
input device.

Userspace cannot distinguish a stranded slot from a finger resting on the
screen. So every real tap arrived as an **additional** contact alongside
the phantoms, which is a multi-touch gesture rather than a press. phosh
routed those to its lockscreen brightness gesture — Lance independently
reported seeing the brightness OSD flash while tapping — and no keypad
button ever received a press. Swipes kept working throughout, because
gestures are computed from deltas and do not need a clean down/up pair.

The decisive measurement, which should have been the *first* thing tried:

    EVIOCGMTSLOTS on /dev/input/event2, with nothing touching the screen:

    slot 0: tracking_id=622   <-- OCCUPIED
    slot 1: tracking_id=624   <-- OCCUPIED
    slot 2: tracking_id=637   <-- OCCUPIED
    slot 4: tracking_id=632   <-- OCCUPIED
    slot 5: tracking_id=636   <-- OCCUPIED

    PHANTOM CONTACTS HELD RIGHT NOW: 5

phoc saw the same thing from the other side and said so plainly:

    phoc-cursor-CRITICAL: Touch point 0 already tracked, ignoring
    phoc-cursor-CRITICAL: Touch point 2 already tracked, ignoring

## The phantoms are display noise, not fingers

Raw packets for two stranded contacts, decoded with the FTS3670 layout:

    slot 3  raw=33 03 7f 8e 28 05 35 5c  ->  x=56,  y=2046
    slot 4  raw=43 01 9f b3 28 fc 32 17  ->  x=27,  y=2547

x=27 and x=56 out of 1440 — hard against the left edge of the panel,
appearing as the display powers up. That is capacitive edge noise coupling
from the display transition, not a touch. Because they are not fingers,
they never produce a leave event.

## The fix

`input: stmfts - drop contacts the controller stops reporting` —
add `INPUT_MT_DROP_UNUSED` to `input_mt_init_slots()`. The driver already
called `input_mt_sync_frame()` at the end of every batch; it simply was not
permitted to act on it.

Two measurements make this safe rather than a guess:

- a finger held **motionless** is re-reported at ~125 Hz (249 interrupts
  per two seconds, dead steady), so a live contact is in every frame and
  can never be dropped
- a stranded contact is **silent**: with two slots still occupied, the
  interrupt count did not move at all across ten seconds
- with nothing touching the panel the controller is completely idle

Live contacts always reported, stale ones never — exactly the condition
`INPUT_MT_DROP_UNUSED` requires.

## Why not the vendor's approach

Downstream `ftm4_ts.c` keeps its own `touch_count` plus per-finger state
and calls `fts_release_all_finger()` whenever the arithmetic disagrees
(count 0 on a leave, an enter while nothing is down), plus on every power
transition after a `FLUSHBUFFER`. It works, but it is a lot of defensive
machinery and **no in-tree driver does it**. `INPUT_MT_DROP_UNUSED` is used
by 26 mainline touchscreen drivers and needs none of it. Prior art
survey is what killed the port of the vendor logic — worth doing before
importing a vendor design.

## Verified on device

Kernel `7.2.0-rc2-g6773b3627fcb`, RAM boot, taps + a held drag + three
lock/wake cycles:

    worst slots held across the run:        1   (the actual finger)
    held at rest:                           0   (CLEAN)
    phoc "Touch point already tracked":     0   (was repeated)
    phoc "Brightness gesture" (taps eaten): 0   (was repeated)
    phoc "Touch event ignored":             0   (was 8)

The held drag kept tracking id 17 alive across consecutive samples, so
`DROP_UNUSED` is not culling stationary contacts — the one way this change
could have made things worse.

**One boot.** The previous build also passed its first phase and only died
once it met a wake. This run did include the wakes, and the counters are
objective rather than subjective, but a second boot is still wanted.

## Battery: one live mitigation should now be reverted

`531e7b10e` raises the A540 GDSC `inactive_period` from 250 ms to
**300000 ms (5 min)**. Aurel's own commit message calls it a diagnostic
with "battery cost real (GDSC stays on during locked idle)". It is live and
the cost is measurable:

    5000000.gpu   autosuspend_delay_ms = 300000
                  runtime_suspended_ms = 0        <-- never suspended
                  runtime_active_ms    = 545000   <-- 100% of uptime

    c901000.display-controller runtime_suspended_ms = 3061  (this one does)

The GPU power domain did not collapse once across the whole boot, including
every screen-off period.

**Its justification is now void.** It was added because "a frozen lockscreen
keypad whose taps land inside the stall window" — that diagnosis is
disproven; the freeze was phantom contacts. Reverting it to the upstream
250 ms is the obvious next experiment: boot, confirm the keypad still
works, and check `runtime_suspended_time` goes above zero.

The touch fixes themselves cost nothing:

- `INPUT_MT_DROP_UNUSED` is bookkeeping inside a sync the driver already
  performed. No timers, wakeups, polling or extra I2C.
- releasing contacts at power-down emits a few input events at blank.
- the `powered` guard **removes** a drain: the old code leaked a
  `regulator_bulk_enable()` reference on every touch open, which could pin
  `touch_vdd`/`touch_avdd` on across screen-off. Both now read `users=1`.

## Four theories the data killed

Recorded so nobody re-runs them:

1. **"Stuck contact" as the explanation** — right in substance, but I
   retracted it after one stream sample showed `open_contacts=0`. Inferring
   state from an event stream was the wrong method; the ioctl reads it
   directly.
2. **phoc rejecting touches** — `Touch event ignored since output DSI-1 is
   disabled` fired only during genuine screen-off. Zero during real taps.
3. **Scale mismatch** — phoc and phosh both report scale 3.0, logical
   480x960 on 1440x2880, and no `GDK_SCALE` in the session env. Aurel's
   August 8th dead-zone mechanism is not what was live.
4. **Slot-ID decode** — the FTS3670 does carry the touch id in the high
   nibble of byte 0. Raw packets show `03`/`04` with slot 0 for one finger,
   matching the vendor driver. `(event[0] & 0xf0) >> 4` was always correct.

Also ruled out: the **fingerprint sensor**. joan's mainline DT has no FP
node, the touchscreen is alone on `blsp1_i2c5`, and no SPI device is bound,
so it cannot disturb the touch bus. Checking it is what prompted decoding
the ghost coordinates, which is how the edge-noise origin was found.

## Method notes worth keeping

- **Read device state, do not infer it.** `EVIOCGMTSLOTS` answered in one
  call what an hour of event-stream reasoning got wrong.
- **The vendor kernel is ground truth.** `getevent` under LineageOS showed
  a clean single-finger tap using one slot with paired down/up, which is
  what proved the fault was ours rather than the hardware.
- **Verify `uname -r` against the expected commit after every boot.** One
  `fastboot boot` silently no-op'd because the phone was in pmOS rather
  than LineageOS and `adb reboot bootloader` had nothing to talk to. The
  version check caught it; otherwise we would have "tested" the old kernel.
- **busybox `grep` has no `--line-buffered`.** A watch built on it dies
  instantly and looks exactly like "no events occurred".

## Still open

1. Second boot to confirm, then squash the stmfts series (it currently
   records the flailing, including a TEMP-DIAG and its revert).
2. Revert `531e7b10e` and re-measure GPU suspend time.
3. `a3b28b8d5` leaves live debug prints in `drivers/gpu/drm/drm_atomic.c`.
4. `0d0456153` and `8974ea3de` are **functional** despite `TEMP-DIAG`
   labels — they carry the touch-power work. Do not blanket-revert by
   label; they need rewording.
5. Rainbow on wake (card 89), wifi firmware (card 90), pwrkey IRQ (card 91)
   remain untouched.
