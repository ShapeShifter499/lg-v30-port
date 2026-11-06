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
bench US998. They are on a local test branch, `ember/hph-ocp-20261106` at
`312847c85fcb`, built as package r76. They are not on `master` or
`joan/latest-clean-test` yet. Tested with one phone, one headset and one boot,
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
  r14 (local branch `ember/hifi-headphones-20261106`, installed on the phone and
  retested: paused on both outputs):
  - The icon: PipeWire reads the port type from the UCM device name up to the first
    non-letter, so `HeadphonesHiFi` came out as Unknown. Renaming the device to
    `Headphones2` gives type Headphones and the headphone icon. Heard and seen on
    the phone.
  - The pause: Phosh pauses when the output stops being headphones, and only
    counts a sink as headphones if its form factor is `headphone` or `headset`, or
    its port is exactly `[Out] Headphones`. The rename alone did not fix this. A
    WirePlumber rule setting `device.form_factor = "headphone"` on the Hi-Fi sink
    did: Firefox paused on 2 of 2 unplugs.
- **Not reproduced: a random slow switch back after plugging in on Hi-Fi.** Lance
  saw it now and then, not badly. In the logged re-plugs, the plug interrupt to
  the jack report took 0.19 seconds (2 on Hi-Fi, 1 on normal), and the default
  output followed 0.3 to 0.4 seconds later on both. No slow case was captured. LG
  puts the chip back in bypass on unplug and we leave it in Hi-Fi, so that is the
  first thing to check.
- **Open: volume can stop matching the slider after switching outputs.** A re-plug
  brought it back into line without moving the slider. Each output remembers its
  own slider position, 37% and 52% at the time. A silent switch and back showed
  the slider, PipeWire gain, mixer and chip register all agreeing, so it was not
  reproduced. Which output and which direction are not known yet.
- **Corrections to this entry as first written:** loud music was not the cause.
  On r74 full-scale sine, noise, bass, bursts and square waves at 52, 75 and 100%
  sink volume raised no interrupts. The 23 ohm figure was one reading, not a
  stable measurement.

**To do:**

- Decide on moving the kernel patches and UCM r14 to the verified branches.
- Catch the volume mismatch while it is happening.
- Consider a Phosh change so numbered headphone ports count without a form factor
  rule.
- Small click when switching between `Headphones` and `HeadphonesHiFi`. LG has
  register sequences for this transition, and our driver does not.
- ES9218P differences from LG: no power-down on unplug, no wait for the impedance
  result before Hi-Fi, and Hi-Fi is not the default output.

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
