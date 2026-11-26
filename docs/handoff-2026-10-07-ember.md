# Handoff 2026-10-07 (Ember, Claude-Code:claude-opus-5-5) — tests that need Lance

Findings: `docs/ember-2026-10-07-osm-bootlog-ipa.md`. Matrix:
`docs/joan-hardware-support-matrix.md` (rows marked 10-07).

## Published today
- Kernel `linux-lg-v30-joan` `joan/latest-clean-test` → `b3dc8621` (fast-forward).
- pmaports `joan/readme-build-guide` → `701b2062e1`: 9 clean commits replacing 57
  local debug-pin commits; `linux-lg-joan` r55 pinned to b3dc8621 (GitHub archive
  sha512 matches the APKBUILD); README hardware table and default apps refreshed.
- `lg-v30-joan-pmos-packages` `19efc7a` (joan-imsd r6, nfc-tags, VoLTE guide).

## Local, not published (waits for the bench)
- Kernel `ef74a2f4` net: ipa: disable NAPI when a channel stop fails (fix for the
  ipa_open BUG after a modem restart). Test kernel r56 built on skyforge.
- pmaports working tree (skyforge): new `fm-radio` app (GTK4, V4L2 radio: tune, seek,
  signal/stereo, RDS name/radiotext, presets), `nfc-tags` r1 (ships an app icon;
  `nfc-symbolic` does not exist in Adwaita, so the launcher showed none).

## First: the phone is wedged
After the modem-restart oops the RTNL lock stayed held: ping answers, sshd accepts but
logins hang, the armed fastboot reboot cannot be triggered. **Hold power to reset it.**
Once it is up I can carry on alone with: r56 + modem restart (by remoteproc name) to
verify the IPA fix; a longer RAM-boot loop for the 1-in-8 silent ADSP; reading the
CPRh OPP voltages to fit EAS `dynamic-power-coefficient` from LG's cost tables;
on-device runs of fm-radio and nfc-tags; charge current at each FCC cooling state
once the battery is below full.

## Needs you there (hands, eyes, ears, or a decision)
1. **Camera**: open Snapshot, check the preview and take a photo (rear IMX351;
   libcamera captures, the app on screen has not been tried).
2. **NFC**: hold an NFC tag to the back while NFC Tags is scanning; write a URL to
   it and read it back.
3. **FM audio**: plug wired headphones (the cable is the antenna), and stand by to
   hold power — the slim2 NGD needed for FM audio has hard-hung the SoC before. The
   FM Radio app's tuner/RDS part can be tried on screen too.
4. **Calls / SMS**: send and receive an SMS; place a call (earpiece and microphone);
   have someone call the phone (VoLTE answers incoming with 480, so the caller
   should land in voicemail). Earpiece audibility is still unconfirmed.
5. **VoLTE decisions**: may joan-imsd create the IMS bearer and REGISTER on its own
   at boot? May I try switching the modem MCFG to see whether the modem can do IMS
   itself?
6. **USB-C display**: a USB-C → HDMI/DP adapter and a monitor. The DP controller,
   PHY DP mode and the 0xff01 altmode are in the tree; it needs a sink to finish.
7. **GPU memory bandwidth**: the downward-DDR-step hang (power cost today, not a
   speed limit) can only be bisected by hanging the SoC repeatedly — needs you to
   power-cycle.
8. **Wireless charging**: put it on a Qi pad (no P9223 driver; see what DC-IN does).
9. **Decision**: per-model DTBs (correct H932/H930 model string + Wi-Fi calibration
   variant) — one DTB today says "US998" on every model.
10. **H932**: if you have one at hand, the r55 image on it (laf boot from the SD).

## Banked 05:20 (after the power cycle)

- Phone: running r57 (`#58-lg-joan`) RAM-booted; SD /boot holds r57.
- IPA: fixed and pushed (r56, r57) — see the findings addendum.
- Uncommitted in skyforge pmaports working tree: `device/testing/fm-radio/` and the
  `nfc-tags` r1 icon change (built: nest `~/joan-images/apps/`). Not yet run on the
  phone. Commit after an on-device run.
- **Next, in Lance's order:**
  1. CPU: EAS energy model in qcom-cpufreq-osm (LUT voltages + coefficients fitted to
     LG's cost tables); then LG bin 0/1 tables so other users' units get DVFS.
  2. Tethering from cellular: Wi-Fi hotspot + USB tethering; test clients with a
     temporary network on a spare Wi-Fi chip of skyforge or nest, never touching
     their LAN links.
  3. Cameras, full bring-up: boot the HI553 front driver (joan/hi553-front-camera-v2,
     Fulgor 10-02), write the S5K3M3 wide driver from libmmcamera_s5k3m3.so tables,
     then Snapshot on screen (needs Lance) for all three.
