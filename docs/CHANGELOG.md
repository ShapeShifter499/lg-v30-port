# LG V30 (joan) port changelog

Newest first. Each entry says how it was checked. "Proven" means tested on
the bench US998; a single phone is not proof for every V30 or every MSM8998
board. Longer notes live in `status-history.md`, `kernel-change-ledger.md` and
`joan-hardware-support-matrix.md`.

## Still to do

See the list at the end of the 2026-11-04 entry. Items that need someone at
the phone are in `BENCH-TESTS-NEEDING-LANCE`.

## 2026-11-06

### Headphones

**State:** four kernel patches fix the alarm flood and the lasting silence on the
bench US998. They are on `joan/latest-clean-test` at `312847c85fcb`, tested as
package r76, and on `master` at `b81e29658fd7`. pmaports `device-lge-joan` at
`64e1b4f0ed72` carries linux-lg-joan r24 and alsa-ucm-conf-lg-joan r14. r24 is booted
and passed on the phone: speech heard on both outputs, and 3 pulls during a tone
on the normal output gave 0 interrupts with the tone returning each time. It
differs from r76 in tfa989x, q6asm-dai and qcom_smgr. Tested with one phone and one headset,
using test tones, speech and Firefox music, which sounded fine. No alarms or
clock warnings over the whole session.

- **Working on r74 and r76: jack detection.** Plug, unplug, headset mic and the
  headset button all report correctly. Impedance readings moved between 11 and
  23 ohms across boots, so treat them as rough.
- **Fixed in r76: alarm flood when the plug is pulled during playback.** The
  codec's headphone amplifier kept driving the open jack, raising about 2,000
  over-current interrupts per second per side. One pull on r74 gave 13,365. LG
  turns the amplifier off on removal and back on after insertion, and our driver
  did not. On r76, 10 pulls and 10 re-inserts in 25 seconds during a tone,
  including wiggling and partial insertion, gave 0 interrupts, and the tone came
  back by ear.
- **Fixed in r76: silence on all headphone paths after the flood, until reboot.**
  Repeated micbias disables released the codec clock too many times, giving the
  `ln_bb_clk1 already disabled` warning. The likely result is `sysclk_users`
  going to -1, which would skip clock setup for later streams. The counter was
  never read directly, so this link is inferred. Silent streams on r74 reported
  no errors. On r76 there were 0 clock warnings, and speech on both outputs was
  heard after the same abuse.
- **Added in r76:** the over-current registers LG sets at start-up
  (`RX_OCP_CTL`, `HPH_OCP_CTL`) and a limit of 20 retries. The retry limit never
  fired in these tests, so it is unexercised. Its patch needs rework before
  upstream, because pm4125 sends no PA-off event.
- **Working on r76: `HeadphonesHiFi`.** Speech was heard at all three test levels.
  It needs a card profile switch to reach. Its slider is a hardware control: 52%
  is the chip's -17 dB. A tone 6 dB below the quietest speech level was not heard.
- **Working on r76: left and right.** Speech reached the correct ear on both
  outputs, with no bleed reported.
- **Not reproduced, so not proven fixed: the first flood.** On r74 a Firefox video
  resumed 3 seconds after plugging in, with the jack reported present, raised
  about 30,000 interrupts per side in 13 seconds. r76 gave 0 interrupts with a tone
  started 0, 1, 2 and 3 seconds after plug-in, and with Firefox resumed about 1.3
  seconds after plug-in, which played clean. That case was never reproduced on r74
  to compare against.
- **Found by Lance on r76, cause known: Hi-Fi was not treated as headphones.** It
  had a speaker icon, and Firefox kept playing on the loudspeaker after an unplug
  instead of pausing. Two separate causes, both fixed in `alsa-ucm-conf-lg-joan`
  r14 (installed on the phone and retested: paused on both outputs):
  - The icon: PipeWire reads the port type from the UCM device name up to the first
    non-letter, so `HeadphonesHiFi` came out as Unknown. Renaming the device to
    `Headphones2` gives type Headphones and the headphone icon. Heard and seen on
    the phone.
  - The pause: Phosh pauses when the output stops being headphones, and only
    counts a sink as headphones if its form factor is `headphone` or `headset`, or
    its port is exactly `[Out] Headphones`. The rename alone did not fix this. A
    WirePlumber rule setting `device.form_factor = "headphone"` on the Hi-Fi sink
    did: Firefox paused on 2 of 2 unplugs.
- **Found on r24, not fixed: a plug-in can go undetected on Hi-Fi.** After fast
  output switching with nothing playing, the ES9218P stayed in Hi-Fi mode. A
  re-plug then raised no interrupt, and the jack stayed `off` for about two
  minutes. Setting `Headphone Mode` to Low Power Bypass made the plug interrupt fire
  within a second, with no re-plug. Seen once. The driver is meant to idle in
  bypass, but selecting Hi-Fi powers the chip up with no stream, so nothing ever
  returns it to bypass. This may also be the random slow switch back Lance noticed
  on Hi-Fi. In the logged re-plugs where detection worked, it took 0.16 to 0.20
  seconds. A fix is on local branch `ember/es9218p-idle-bypass-20261106` at
  `fe54d49f576e`, built as r25 and booted, not pushed. Checked with a silent
  stream: with Hi-Fi selected and idle the chip stays in reset, it comes up with
  the right registers when a stream opens, and it returns to reset afterwards.
  Tested by Lance on r25: 4 re-plugs on idle Hi-Fi all detected, including after
  fast switching, speech heard on both outputs, and clean Firefox resumes with the
  chip registers matching the good snapshot. Hi-Fi sounded louder than on r24 at
  the same settings, with Lance turning it down from 41% to 29%. The cause is not
  measured.
- **Open: the Phosh slider can get stuck on the wrong output.** After several
  switches and a re-plug, audio was on Hi-Fi and PipeWire's default was Hi-Fi, but
  Phosh showed a speaker icon, and nudging its slider moved the Speaker sink from
  67% to 53% and left Hi-Fi at 52%. Phosh only follows the output when
  libgnome-volume-control reports a change. Why that was missed is not known.
  Each output also keeps its own slider position.
- **Open, not explained: Hi-Fi sounded noticeably quieter than its slider** after a
  few switches, until a re-plug. The slider, mixer, chip volume, analog volume and
  Firefox's stream volume read the same before and after that re-plug. The stuck
  slider does not account for this on its own. Caught live: on the same video, the
  signal entering the sink rose from -23.9 to -15.0 dBFS RMS after a re-plug, with
  the same reported Firefox volume, sink volume, mixer controls and chip settings.
  So the loss is before the sink. A test stream held its exact level through four
  output switches, which points at Firefox or how its stream is handled, but that
  is not proven. Firefox also writes the page's volume into its stream volume, so
  that number can move by itself.
- **Upstream:** no matching report found for the slider or the quiet stream. The
  pause gap is known: WirePlumber issue 860 asks for pausing on 3.5mm unplug and is
  open with no comments. WirePlumber only pauses when an output is removed. Phosh
  issue 1273 plans to drop Phosh's own pause in favour of WirePlumber, which would
  likely lose it here, because our sinks are not removed on unplug. In Phosh, slider updates also write
  back to the stream without checking `setting_volume`, which may explain the
  jumpy slider. Not proven.
- **Corrections to this entry as first written:** loud music was not the cause.
  On r74 full-scale sine, noise, bass, bursts and square waves at 52, 75 and 100%
  sink volume raised no interrupts. The 23 ohm figure was one reading, not a
  stable measurement.

**To do:**

- Check whether callaudiod causes the default output's brief flip to Speaker on
  each switch. It forces the first new sink as default, even outside calls.
- Try a WirePlumber script that pauses when the headphone port goes unavailable,
  and offer it on issue 860 if it works.
- Find why Phosh misses the output change, and catch the quiet Hi-Fi case with a
  full snapshot.
- Consider a Phosh change so numbered headphone ports count without a form factor
  rule.
- Small click when switching between `Headphones` and `HeadphonesHiFi`. LG has
  register sequences for this transition, and our driver does not.
- ES9218P differences from LG: no power-down on unplug, no wait for the impedance
  result before Hi-Fi, and Hi-Fi is not the default output.

### Sensors

- **State:** pushed. Kernel `master` at `7c1fbdb63002` (tested as r29),
  `joan/latest-clean-test` at `0f643b34c44a` (same seven commits, not booted; its
  sensor and ES9218P code differs from r29 only by its existing typed QMI release
  callback), pmaports `device-lge-joan` at `7d98db529a` (linux r29). The GitHub
  tarball matches the recipe. r29 is booted and every SMGR sensor reads through the
  driver: accelerometer, gyro, magnetometer, barometer, proximity and light. 0 QMI
  encode errors. Lance tested proximity, gyro and rotation by hand on r29.
- **Added: ambient light.** The sensor DSP lists "LGE Light" (AMS TAOS) as data type
  1 of sensor 0x28, and the driver only requested type 0. It is now a `qcom-smgr-light`
  IIO device, and iio-sensor-proxy reports it in lux (7 lux at the desk, lit by a lamp
  and sunlight through blinds).
- **Light level check:** peak 33 lux against about 60 on a Samsung Fold 5 in the same
  room, a rough check by one other phone, not a calibration. It read 0 under every
  cover. Streaming and single reads agree. LG's black glass coefficients are loaded;
  the silver glass ones are not, and this phone's glass colour is not confirmed.
- **Fixed: failed sensor requests.** The gyro's -EINVAL, and the test read stuck
  after it, had two causes. The kernel's QMI code treats length fields as 32-bit,
  but the driver declared them 8-bit, so stray bytes could corrupt a request. The
  one-shot read also kept its lock after a failed request. Both fixed.
- **Fixed: proximity on the desktop.** The driver reported 0 for near, opposite to
  the IIO rule, and published no near level, so iio-sensor-proxy refused the sensor.
  `fd43578cc244` fixes both in the driver, with no device-specific udev rule. On r29
  the warning is gone and the proxy tracks covers (near level 1638). It also went
  near during the spin and rotation steps, probably from Lance's hand, not confirmed.
  Blanking the screen during a call is not tested.
- **Fixed: gyro timeouts.** About 1 read in 8 timed out on r27. On r29 a one-shot
  read takes about 293 ms when the gyro has been idle for 2 seconds, which is why
  the 250 ms wait was marginal. `2ccc6a540306` waits up to 1 s. 372 reads on r29, 0
  errors.
- **Fixed: Z axis flipped.** Lying screen up, the phone reported face-down (-9.71
  m/s^2) because the driver's mount matrix was a reflection, not a rotation.
  `7c1fbdb63002` negates Z. r29 reports face-up. Gyro Z after the matrix is positive
  for the counter-clockwise spin, as the kernel docs require, assuming the spins were
  done in the order asked. One 1-second face-down reading appeared while the phone
  was being put down.
- **Rotation still works:** iio-sensor-proxy reported left-up, right-up, bottom-up
  and normal on r29. Whether the screen itself follows was not reported.
- **Open: no desktop compass.** The magnetometer reads through IIO, but
  iio-sensor-proxy never uses raw magnetometers. It needs a ready-made heading, the
  IIO channel `in_rot_from_north_magnetic_tilt_comp`, or its SSC path, which does not
  apply to this SMGR-era DSP. Raw magnetometers are its open issue 310, and an
  earlier attempt (MR 316) was closed. Our raw field also reads about 1.5 at rest,
  which would be too strong for Earth's field if the unit is gauss, so it probably
  needs calibration before it can give a heading.
- **Compass, DSP services checked: no usable heading yet.** The DSP offers Rotation
  Vector (274), Orientation (279) and Filtered Mag (273). Orientation stops changing
  0.3 s after it starts. Rotation Vector does follow turns: four clockwise quarter
  turns read +83, +86, +91 and +77 degrees. It is not a compass, though: its accuracy
  byte stayed 0 after a figure-8, and it reported about 62 degrees of tilt on a phone
  lying flat by the end of a 157 s run. The phone also read about 205 degrees at what
  appears to be the north hold (which hold it was is inferred from the turn sequence).
  Filtered Mag is not live field data: its strength stayed within 0.0002 through a
  figure-8, and at rest it swung 37 degrees in 36 s while the raw magnetometer moved
  0.5 degrees. Raw gyro bias at rest is about 1.1 deg/s, which matches that 1.03 deg/s
  swing. Rotation Vector drifted more slowly, at 0.57 deg/s, so it is not simply the
  same integration. Cause not yet known.
- **Cause found, fix not yet tested: the DSP's algorithms were running on zeros.**
  A boot-time trace shows the DSP making 79 registry requests. Five reads failed
  because `sns-reg` had no map for those groups (2500 gyro calibration, 2970 mag
  calibration, 2610, 2980, 2990), and three writes (2690, 2691, 3050) got no reply.
  The phone's own registry, `/sns/cal/sns.reg` on the `sns` partition, shows 187
  non-zero values our registry lacks, including factory gyro bias and scale (group
  10), accel factory calibration (group 0), and tuning for Filtered Mag, Gravity and
  Orientation. An earlier note here said missing items were not the cause; that was
  wrong, it only held for the 328 items in LG's config. Group layouts come from the
  tables in LG's `sensors.qti`, checked against `sns-reg`'s map (64 of 68 groups
  identical, all sizes equal) and against `sns.reg`, whose size matches exactly.
  `sns-reg` r1 adds the groups and answers writes. It and 95 registry values were
  booted on the bench phone (kernel still r29). Groups 2690 and 2800 were left alone
  because they hold working hardware setup. Factory values are per handset, so they
  cannot ship in a package as they are.
- **Result on the phone: drift fixed, compass still open.** Services 320 (mag cal) and
  321 (gyro cal) now exist. At rest, raw gyro bias fell from 1.10 to 0.04 deg/s,
  Filtered Mag's swing from 37 degrees in 36 s to 0.07 in 44 s, and Rotation Vector's
  drift from 20 degrees in 36 s to under 0.1 in 44 s. The phone now reads flat when
  flat. Orientation no longer freezes. Gyro calibration reports accuracy 3 and writes
  learned values back. Magnetometer calibration does not converge: after a 60 s tumble
  it sent no reports, its 2980 writes held zero bias, and accuracy stayed 0. A sphere
  fit on the raw magnetometer gives a fixed offset of about 1.47 and a field of about
  0.45 (close to Earth's if the unit is gauss), so the offset is about three times the
  signal. That matches Orientation's heading barely moving through a full turn. Heading
  from the raw data with that fit removed stepped +106, +81, +69 and +43 degrees and
  read about 157 at the north hold, so one rough fit is not a usable compass.
  iio-sensor-proxy still sees tilt, light and proximity.
- **Compass now works on the bench phone, roughly.** Preloading that fitted offset
  into group 2980 (`3901` = 1, `3903`-`3905`, the negated fit, inferred from how the
  DSP applies gyro bias) did not change readings at boot. About 110 s into a hand test
  the DSP's calibration locked: accuracy rose from 0 to 2, the field fell from about
  1.6 to 0.4-0.7, and the raw IIO magnetometer became calibrated too. Against a Fold 5
  compass, Rotation Vector read 131 at a 46 degree bearing, 81-91 at north and 172 a
  quarter turn later, a fixed difference of about 85 degrees, which fits the DSP's axes
  being swapped from the phone's. The quarter turn after that was noisy (274-293) and
  the rest was less clear, so expect about 10-15 degrees at best. Near the end 61 of
  9,537 samples read accuracy 0 with a zero heading. It is not known whether the
  preload caused the lock: one run without it did not lock and one run with it did.
  The lock survived stopping every client. The DSP has not written the learned offset
  back to the registry, so it may not survive a reboot. Rotation Vector, Orientation
  and raw IIO all benefit, but the desktop still shows "No compass" until a driver
  exposes a heading. On these settings the screen followed rotation by hand. No
  upside-down event was logged because the phone was held screen-down, which counts as
  tilt. Proximity logged 11 near events where 3 were asked for; Lance's arm was
  brushing near the top. With nothing near it there were 0 events in 80 s idle and 0
  in about 70 s under the full logging load.
- **Shared settings alone do most of it.** Device package r38 adds 84 values and
  leaves out factory biases and the magnetometer preload. Booted with `sns-reg` r1:
  services 320 and 321 appear, Rotation Vector held still at rest, and the DSP learned
  the gyro bias by itself within a few minutes (1.17 to 0.07 deg/s, group 2610 values
  close to factory plus learned on the earlier boot). So factory gyro values are not
  needed. The 84 come from one handset, so "shared" is a judgement by kind. Compass
  lock has not been tried on this set.
- **Open: VL53L0X laser.** It fails its model ID read at boot on r25 and is not
  bound. It was not retried with nobody at the phone, because a past probe of it or
  the camera sensor hung the SoC.

### Bench note

- A diagnostic script read debugfs regmaps it should not have, including
  interconnect and clock-controller hardware registers. It never returned, and
  the phone then answered ping but not SSH. The script is the likely cause. This
  was a test mistake, not a phone fault.
- The `sink []` failures in the audio tests were also a test problem. The user's
  PipeWire only runs while that user has a session, so it stops when the last SSH
  session closes. Keep one session open during a test run.

## 2026-11-04

**Release state:** kernel `master` `15666334cc98`; the code before the Bluetooth
fix passed 20 of 20 boots with Wi-Fi, sound and touch up each time. pmaports default branch `device-lge-joan` now
carries every package: linux-lg-joan r23, device-lg-joan r37, joan-imsd r13, UCM r13.
`joan/latest-clean-test` carries the same fixes at `de3bd3e3639c`, boot-tested as
r74: no failed units, and VoLTE registers by itself at boot.

### Display

- **Fixed: UI jitter while scrolling and navigating.** The kernel refused
  about one screen update per frame. phoc lists the unused cursor plane in
  every commit, and that plane's placeholder ("fake") commit was only marked
  finished after msm's page-flip event had already told phoc to go ahead.
  Failed commits dropped from 5169 per 5576 frames to 0 per 3534. Reported as
  "night and day" in use. Same race as Ville Syrjala's 2018 fix 2de42f79bb21,
  which only narrowed it.
- **Fixed: brightness writes failing with the screen off.** The panel driver
  returned an error while there was no DSI link, so `systemd-backlight` looked
  failed. The stored level is now applied when the panel enables.

### Memory

- **Fixed: hang when leaving 1804 MHz DDR.** Bandwidth votes above 4.29 GB/s
  were cut to 32 bits on their way to the RPM, so 13.76 GB/s arrived as 0.88
  GB/s. They are now sent as 64-bit values, as LG's kernel does. 30 of 30
  load-and-drop cycles survived with latency confirming every step (146 ns at
  1804, 155 ns at 1555, 347 ns at 412 MHz). The drop used to hang the phone on
  the first attempt.
- **Measured: true DDR floor.** With every voter gone, latency is about
  1100-1175 ns and read speed 1.6-2.0 GB/s. The earlier "412 MHz floor" was the
  stuck USB vote.
- **Not fixed: 1804 MHz under real load.** The 1555 MHz cap stays. With the cap
  removed and LG's top BWMON and GPU values restored, r71 reset itself about
  30-40 seconds into boot, twice, with no panic text, once the desktop and GPU
  started. The drop test above had only run with the CPUs capped and little
  else busy. The work is kept on `ember/ddr-1804-uncap-wip-20261104`. A capped
  build with the same splash settings boots normally.
- Boot log: dropped two false `-EBUSY` errors from bwmon, whose claim on a
  shared region always fails by design.

### USB

- **Fixed: unplugging was never noticed.** The legacy dwc3 glue forced "VBUS
  present" on and only extcon could clear it, which joan does not have. The
  msm8998 USB node now uses the flattened `qcom,snps-dwc3` binding, so a detach
  reaches the controller. It suspends and drops its 2.5 GB/s memory vote about
  6 seconds after unplugging, and reconnects within a second of replugging.
- **Fixed: a cable attached at boot was invisible.** The PMI8998 port raises no
  interrupt for a partner already attached, so the driver now reads the state
  when toggling starts, like LG's `smb2_determine_initial_status()`.
- Added a udev rule so the controller may runtime-suspend. This is what lets
  DDR fall on battery.
- Boot log: a normal hard-reset signal no longer logs as an error.

### Calling

- **New: outgoing VoLTE from the normal Calls app**, with audio both ways on the
  earpiece and a working speaker button, tested on T-Mobile US. This modem has
  no IMS of its own, so `joan-imsd` runs it on the main processor, and a small
  local SIP bridge connects Calls to it. Calls itself is unchanged, and the
  account is created on first login.
- New `Voice Call` UCM verb for in-call audio; HiFi is untouched.
- `joan-imsd` now starts with no manual setup, reads its identity from the SIM,
  and survives quick restarts.

### Bluetooth

- **Fixed: discovery.** The kernel used extended advertising with legacy
  scanning, and the chip rejects that mix. Discovery now finds nearby devices.
  Jev flagged the log line that led to this.

### Brightness

- **Fixed: dark start.** The level that kept appearing, 9 of 255, was Phosh's idle
  dim: 30 on its logarithmic range lands there on this OLED panel, and the login
  screen hands it on to the session. `idle-brightness` is now 60, raw 37.

### Packaging

- **Fixed: the default branch had no device packages**, and the working set
  was spread over several branches, with the sensor registry uncommitted.
  Consolidated in `joan/integration-20261104`: UCM r12, device package, sns-reg
  and LG's sensor registry, AWB window.
- **Fixed: missing `quiet` and splash, which caused the text flash after the
  first unlock.** `deviceinfo_kernel_cmdline` is deprecated and makes
  boot-deploy skip `kernel-cmdline.d`, so postmarketOS's own boot settings were
  lost. Device options now live in `/usr/lib/kernel-cmdline.d/30-lg-joan.conf`.
- Firefox hardware video decode is now enabled by default through a preference
  file, for the Venus block. The temp/ffmpeg patches it needs were already in
  the fork.
- joan-imsd needs no manual setup. It reads the identity from the SIM, waits
  for the modem, and configures the IMS interface. Tested on T-Mobile US with
  only the SIM: `REGISTERED` with SIP 200 OK.

- Waydroid: the kernel meets the wiki's requirements, and a new
  `device-lg-joan-waydroid` subpackage, pulled in automatically with `waydroid`,
  opens the firewall for `waydroid0`. Images install and the container starts.
  Waydroid stays optional. A running Android session is not tested yet.

### Checked remotely on r74

- All three cameras streamed 15 of 15 frames. Colour and focus still need eyes.
- Venus decoded an H.264 clip through `h264_v4l2m2m`, with 222 Venus interrupts.
  Firefox itself is not retested.
- FM tuner opens as `radio-qca-fm`; NFC exposes `/org/neard/nfc0`, with neard
  started on demand over D-Bus. No station or tag tested.
- All 8 cores at full load for 42 seconds: CPUs near 80 C, under the 85 C trip,
  with the big cores easing from 2457 to 2208 MHz. Longer runs are untested.

### Withdrawn claims from this session

- "30 of 30 from 1804 MHz" on r69: the clock was not moving, so that run proved
  nothing. Mixed 4 and 8 byte votes left DDR stuck high. Repeated on r70 with
  latency checks.
- A Type-C fix went into the PM8150B driver, which this phone does not run. It
  was dropped and rewritten in `qcom_pmic_typec_pmi8998.c`.
- r71, which removed the 1555 MHz cap, crashed on boot; see Memory.
- "OpenIMSd is the route for calling on this phone": wrong. Our 2026-08-26 notes
  had already shown the modem firmware lacks the service it needs.
- "The backlight file is corrupted": the leftover line is harmless, since only
  the first line is read. The real error was the panel driver.

### Known issues

- Silent ADSP on roughly 1 in 75 boots; needs glink/APR tracing on a failing
  boot.
- `battery overvoltage detected` trips about once per boot while charging. The
  hardware stops charging by itself. Lead: our charger driver clears
  `BAT_OV_ECC_BIT`, which LG's leaves alone.
- Charger setup differs from LG's in other places: charge inhibit threshold,
  ICL override and AICL rerun.
- VL53L0X laser autofocus sensor fails to probe (`-ENXIO`).
- wcd934x logs twelve harmless "no paths" warnings; ath10k logs a harmless
  board-data fallback; Bluetooth logs harmless reassembly errors during setup.
- Incoming calls do not work yet. The network delivers them over TCP inside
  IPsec, which `joan-imsd`'s user-space ESP cannot carry. Kernel ESP is in the
  code as an opt-in, but registration through it gets no reply yet.
- No ringback tone on outgoing calls: Calls 50 crashes when an alerting call is
  answered, so the bridge does not forward ringing.
- No VoLTE or VoWiFi indicator: neither Calls nor Phosh has one. VoWiFi is not
  implemented.
