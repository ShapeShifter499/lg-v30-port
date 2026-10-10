# Kernel 7.3 port, boot and bench results (2026-10-09)

Ember, Claude-Code:claude-opus-5-5. Bench: US998 on nest USB, pmOS on the SD, RAM boot
of the boot.img that `apk add linux-lg-joan` generated on the device (tools/bench/ramboot.sh,
armed send). Nothing flashed.

## Kernel
- `joan/latest-clean-test` 3f7fcabf + `Merge tag 'v7.3-rc6'` (dd6f9f84). 8 conflicting files
  (qcom_usb_vbus PMI8998 re-expressed on upstream's PM4125 table; qmp-usbc reset lists and
  probe order; q6dsp port ids; qcom_pas renames; msm_gem_submit vm; vl53l0x claim_direct).
- Silent breakages fixed in the merge: joan SLIMBUS_7/8 ids (150-152) collided with new
  LPI_MI2S ids -> 153-155; thermal-weighted-adc needs MODULE_IMPORT_NS("IIO_CONSUMER");
  fbdev VIRTFB flag duplicated (upstream took the same fix elsewhere) -> joan copy dropped.
- Reverted: 6a5719cc + 544d85de (qrtr HELLO on endpoint register; crash-loops the MSM8998
  modem, see evidence/2026-10-07-qrtr-hello-modem-crash). Packaged qrtr.ko has only ns.c
  say_hello. 7.3 brings 3cbfd627ee72 (IPA TX-queue wake, CVE-2026-80997).
- Config: CRYPTO_DEV_QCOM_RNG -> HW_RANDOM_QCOM=m; CRYPTO_DEV_QCE is BROKEN upstream (drops);
  PROC_SYSCTL removed upstream. Build: 0 compiler/dtc warnings.

## Boot (r0 cdce1fb7, r1 568161b0)
- `systemctl is-system-running` = running, 0 failed units, ~30 s to USB net.
- Kernel warnings: same set as r60 (r60-baseline-dmesg.txt vs v73r0-dmesg-warn.txt), no new ones.
- Jev triage (TypeSafe jev-latest via jev-bootlog-triage.py): category choice was sane on a
  positive control (JOANDBG->debug 0.92, phy init -16 -> functional 0.96, WCD mux -> benign
  0.99); its needs_change noul did not discriminate (0.5-0.8 everywhere) and is ignored. The
  NEW/same column in v73r1-triage.tsv is wrong (prefix normalisation differs from the
  baseline file) - read the category only.
- Real findings: callaudiod "No suitable card found" (UCM has only a HiFi verb, no Voice Call
  -> Deck #164); soc-qcom-pulseaudio's call-audio-idle-suspend-workaround exits 143 on session
  stop (generic pmOS, cosmetic, upstream); supply dummies (tfa989x vddd, ath10k vdd-3.3-ch1,
  adreno vddcx) match LG's DT, which gives none; PHY DP init -16 belongs to the unported DP.
- boot.img: gzip initramfs made it 32,198,656 B > aboot limit 32,108,544 B. zstd:best ->
  31,223,808 B (device-lg-joan r26 deviceinfo_initfs_compression). The uncompressed initramfs
  is ~32 MB of generic pmOS (systemd, libcrypto, btrfs/xfs).

## CPU / GPU / thermal
- 1 gold busy: 2457.6 MHz. 4 gold busy: 2361.6 MHz, then cpufreq cooling at the 85 °C passive
  trip: 2323.2 -> 2265.6 as the hottest zone hit 84.5-85.1 °C. All 8 busy: silver 1900.8.
- schedutil rate_limit_us 1500 (driver transition latency 1 ms); retention idle states in use.
- Gold skin caps were off by one OPP after the 2457.6 row: fixed (3352a3e5).
- CPRh open-loop vadj: 7 corners 4 mV low vs LG -> fixed (b6a56608). VDD_GFX max 1088 mV (27dc01c8).
- GPU: devfreq 257-710 MHz; glmark2-es2-drm off-screen 168 at 710 MHz. MX (pm8998 S9 0x2c40/41)
  reads 896 mV idle and at 710 MHz; Linux casts no MX vote (downstream votes TURBO at 670/710).
- Venus: 1080p30 H.264 300/300 frames via h264_v4l2m2m at 194 fps.

## Cameras
- IMX351 (main): streams; raw torch frame imx351-raw-torch-gray.png. Processed frames in the dark
  bench room are near-black (same as 2026-10-07); colour/brightness need a lit scene.
- S5K3M3 (wide, new driver): binds, streams 120 fps / 2080x1560; s5k3m3-raw-torch-gray.png
  (raw is 180° from the main camera, matching DT rotation 90 vs 270).
- HI553 (front): streams 2560x1920 at 30 fps on 2 lanes after c8789cfe; hi553-testpattern.png is
  the sensor test pattern (green sites) through CSIPHY2 -> CSID0 -> VFE.
- Pin-state bug found on the way: two same-named &tlmm states merged silently in dtc (front
  camera's GPIO 15 overrode the wide camera's GPIO 14) -> wide chip-ID NACK -> CAMSS graph
  incomplete -> no camera at all. Fixed c8c46a8b.
- LG chromatix colour matrices for all three sensors: nest
  ~/.ember/workspace/joan-camera-tuning-20261009/ (to go into temp/libcamera after a lit check).
- Autofocus: libcamera 0.7.2/master has no AF for the simple pipeline; patchwork series 5814
  (manual LensPosition) is the starting point.
