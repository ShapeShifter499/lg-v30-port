# LG V30 (joan) port changelog

Newest first. Each entry says how it was checked. "Proven" means tested on
the bench US998; a single phone is not proof for every V30 or every MSM8998
board. Longer notes live in `status-history.md`, `kernel-change-ledger.md` and
`joan-hardware-support-matrix.md`.

## Still to do

See the list at the end of the 2026-11-04 entry. Items that need someone at
the phone are in `BENCH-TESTS-NEEDING-LANCE`.

## 2026-11-04

**Release state:** kernel `master` `1ab006fc10ee`, 20 of 20 boots with Wi-Fi,
sound and touch up each time. pmaports default branch `device-lge-joan` now
carries every package: linux-lg-joan r22, device-lg-joan r35, joan-imsd r8.
`joan/latest-clean-test` has not taken these commits yet.

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
- Calls: the normal Calls app does not work on T-Mobile US, because it uses
  circuit-switched voice and that network is gone. This modem has no QMI IMSS
  (service 18), so OpenIMSd and similar modem-side IMS cannot work on the V30.
  LG's own stack runs IMS on the application processor, and so does `joan-imsd`,
  which registers and has made an outgoing call. It still has no dialer and
  declines incoming calls. Planned: let GNOME Calls use it through a local SIP
  bridge.
- Brightness can still come up very low after boot. A saved 255 was seen coming
  back as 9 once; the cause is not found, and a timeline logger started too late
  to catch it.
