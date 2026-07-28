# joan: DSI/frame serialisation for the brightness slider — fix written, device test failed

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-07-28

Session state around commits `15d1ea453` and `b64896e7e`. The ledger entry
K173/K174 carries the same conclusions in the running record; this is the
narrative version, including what was tried and rejected.

## One-line status

**k174 REGRESSES: it boots pmOS, then dies after ~25 seconds.** Do not build on
this image. The slider was never reached, so the fix itself is still untested;
what is now known is that the patch breaks the boot.

## The regression — read this first

`dmesg` on nym-nest, after a clean `RAMBOOT_OK` (send 0.592 s, boot 5.094 s):

    [330249] Product: LG V30 / SerialNumber: postmarketOS / cdc_ncm registered
    [330274] usb 1-1.5: USB disconnect          <- 25 s later
    [330291] idProduct=4ee7                     <- fell back to LineageOS

So the kernel boots and userspace comes up far enough to register the USB
gadget, then the device dies ~25 s in. k172 stayed up indefinitely, so this is
the patch, not the device.

25 s is about when greetd/phosh starts the display session. That is the first
moment DCS commands flow while `dpu_enc->enabled` is true, i.e. the first
moment `dsi_mgr_wait_for_link_idle()` actually waits instead of returning
early. That is the prime suspect and the place to start.

Leads worth checking, cheapest first:

- Is `msm_dsi_manager_cmd_xfer()` reachable *from the commit path itself*?
  If a DCS write happens while the display thread holds `pending_kickoff_cnt`,
  the new helper blocks the very thread that would decrement it — a 50 ms
  stall per command at best, and if it is on the kickoff path, a self-wait.
  The 50 ms cap means it should time out rather than hang forever, so if the
  symptom is a hard reset, suspect the watchdog firing on accumulated stalls.
- Panel init sends a long burst of DCS (including the 29-byte 0xd9). At 50 ms
  each that is seconds of stall during enable.
- Get the evidence rather than guess: the device dies before ssh is usable, so
  console or ramoops is needed. Note ramoops is scrubbed by the LG boot chain
  on this device — positive-control any log channel before trusting silence.

A cheap bisect exists: the two commits are independent. Build `15d1ea453`
alone (brightness ceiling + params, no DSI change) and confirm it boots. That
separates the panel change from the serialisation change in one boot.

## Flashing now works

The transfer stalls are solved: the cause was idle time in the bootloader.
Starting the transfer the instant fastboot answers gives a 0.592 s send.
`/tmp/ramboot-joan.sh` on nym-nest does this end to end from either LineageOS
or a wedged state:

    ssh nym-nest-family '/tmp/ramboot-joan.sh /tmp/boot-joan-k174.img'

Proof it actually landed: `uname -r` should read `7.2.0-rc2-gb64896e7eec3`
(k172 and the first k173 build both reported `72a8deb11933-dirty`, so the
version string was useless as a marker until these commits existed), and
`/sys/module/panel_lg_sw43402/parameters/` should contain `sw43402_dbv_max`.

## The test that matters — ONCE IT BOOTS AND STAYS UP

Drag the brightness slider while something is animating. That is the exact
reproducer: a stream of WRDISBV commands landing while the compositor holds
the DSI link. Before this patch it scrambles the screen and the garbage
survives until a full repaint.

Also worth checking in the same boot: that the slider still reaches both ends,
and that dmesg carries no new DPU `*ERROR*` lines during modeset. An earlier
version of this patch produced 58 of them; the `!dpu_enc->enabled` guard is
what removed them, and a regression there would show up immediately at boot.

Remember the standing test protocol: blind step-and-ask, one value at a time.
It has caught a wrong "it works" conclusion three times on this panel now.

## What the fix is, and why the obvious version was wrong

A command-mode panel carries pixels and DCS traffic on one DSI link.
`msm_dsi_manager_cmd_xfer()` starts a transfer with no knowledge that the DPU
owns the link for a frame. The collision truncates the frame, and DSC 1.1
turns a truncated frame into whole-screen garbage.

The first attempt (`863a30a79`, reverted) called
`dpu_encoder_wait_for_tx_complete()` from the DSI thread and froze the
compositor with a fence stuck mid-commit. The wait itself was correct. The
bookkeeping wrapped around it was not: `_dpu_encoder_phys_cmd_wait_for_idle()`
runs frame-done recovery on timeout and clears `pp_timeout_report_cnt` on
success, and both belong to the display thread. A second caller either fires
recovery at a healthy commit or clears a counter the display thread is using.

The landed version (`b64896e7e`) is `dpu_encoder_wait_for_link_idle()`: a bare
`wait_event_timeout()` on `pending_kickoff_wq` / `pending_kickoff_cnt`. No
recovery, no counter writes, no logging. Safe for any number of waiters
because `wait_event_timeout()` does not consume the wakeup. Capped at 50 ms,
and on timeout it sends the command anyway — a late brightness update beats a
dropped one. Reached through an optional `msm_kms_funcs` op, so non-DPU msm
targets are untouched.

Note for anyone tempted to retry the simpler version: it compiles, it looks
right, and it hangs the display. That is why the reverted attempt is written
into the public ledger alongside the working one.

## Commits (branch joan/gpu-bringup, NOT pushed)

- `15d1ea453` drm/panel: sw43402: DBV ceiling 251 -> 255, both endpoints as
  module params. 251 was where `lge,blmap_v1` stopped, not a hardware limit;
  `lge,blmap-ex` reaches 255 and the top is visibly different on glass.
  Range is now 6..255 against LG's 30..251, roughly 40x rather than 8x.
- `b64896e7e` drm/msm/dsi: the serialisation above.
- `1963ab5` (lg-v30-port) ledger K173/K174 + the flashing traps below.

## Two facts this session cost real time to learn

**On joan, fastboot mode looks like the LG logo.** A phone "stuck at the LG
logo" that still shows `18d1:d00d` in `lsusb` is sitting in the bootloader and
is fine. I misread a host-side transfer failure as a dead kernel. Check
`lsusb` before concluding anything about the kernel.

**pmOS is RAM-booted only.** The boot partition holds LineageOS, so any
reboot, crash or aboot timeout drops back to LineageOS. That is normal, not a
symptom. It also means no kernel this session was ever persistent.

Supporting details: the phone is `172.16.42.1` and the host is `172.16.42.2`
(this orientation gets reversed every single time); key `id_pi_migration` on
nym-nest, user `user`. From pmOS, busybox `reboot` cannot pass a mode string,
so reach the bootloader with the syscall —
`python3 -c 'import ctypes,os; ctypes.CDLL(None).syscall(142, 0xfee1dead, 0x28121969, 0xA1B2C3D4, b"bootloader")'`
(arm64 `__NR_reboot` = 142). From LineageOS, `adb reboot bootloader`.

aboot wedges its fastboot endpoint if it idles, and a stalled transfer leaves
it enumerating but unclaimable — `fastboot devices` lists it while every real
command returns `< waiting for any device >`. Only a forced power cycle
clears it. `/tmp/ramboot-joan.sh` exists to stay out of that state: it starts
the transfer the instant fastboot answers and always retries from a fresh
bootloader entry rather than against a wedged one.

## Open, in rough priority order

1. Verify k174 on device. Everything above is theory until then.
2. Push `joan/gpu-bringup`. Still unpushed as of this handoff.
3. Sensors: accel, gyro, ALS, prox are all behind the SLPI sensor DSP with no
   in-tree IIO client. Deferred by agreement; wants a checklist first.
4. Wifi/BT (M5).
