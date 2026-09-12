# Order of operations: jack/mic/buttons → cellular (2026-09-11 plan)

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: ZCode:zai-coding-plan/GLM-5.3

Goal sequence set by Lance: nail the headphone jack (detection, in-line
mic, buttons), then wire cellular calls into pmOS. One kernel build
(pkgrel 14 = tip 2b6ecf829cd7 + ESP modules + PM debug) serves phases 1-3.

## Phase 1 — headphone jack, in-line mic, buttons (Lance's hands + headset)

Boot pkgrel-14 kernel via the staged image (RAM boot only):

    # on nest
    sudo -n fastboot boot ~/joan-test-assets/jack-cellular-20260911/boot-joan-pmos-r14-jack-cellular-20260911.img
    # (sha256 0c99c3213aafa050; cmdline masks usb-signaller so the gadget
    #  survives until the r14 device package installs developer-default;
    #  then sshd answers on 172.16.42.1, user/147147, via sudo)

First thing on boot — make the running kernel self-consistent and bring
developer-default + the new daemons in:

    scp alsa-ucm + device apks ... (or from nest ~/joan-test-assets/jack-cellular-20260911/)
    sudo apk add --allow-untrusted ./device-lge-joan-1-r14.apk ./linux-lge-joan-7.2.0_rc2-r14.apk
    (installkernel + depmod make /lib/modules/7.2.0-rc2 match the running
     kernel; developer-default ends the signaller teardown for future boots)

Then:

1. **Verify the fix took** (before any headset work):
   - `grep wcd934x /proc/interrupts` — note parent fire count at idle
     (one probe-time fire is expected history; what matters is growth on events)
   - `doas cat /sys/kernel/debug/regmap/*wcd*/registers | grep -E "^0461"` —
     LEVEL bytes must read `01 00 00 00` (the patch's write). If they read
     reset values, the fix did not land in this build.
2. **Mechanical switch**: plug/unplug a 4-pole headset slowly several times:
   - `evtest` on the jack input node — expect insert/remove events
   - parent IRQ count should grow per event
3. **Buttons**: press each of the three remote buttons — expect
   KEY_PLAYPAUSE / KEY_VOICECOMMAND / KEY_VOLUMEUP/KEY_VOLUMEDOWN distinctly
   (all-PLAYPAUSE = threshold ladder did not take; the 75/150/237 mV ladder
   has been in the DTS since Ember's commit)
4. **In-line mic capture**: with headset in:
   - clear sticky TX state first (AIF*_CAP Mixer SLIM TX* bits — reset rule!)
   - `alsaucm -c 0 set _verb HiFi set _enadev Headset`
   - `arecord -D hw:0,1 -f S16_LE -r 48000 -c 1 -d 5 /tmp/hs.wav`
   - speak during capture; verify 1 kHz tone/voice shows in spectrogram;
     ADC2 should now be the source
5. **Pass criteria**: insert/remove events + ≥3 distinct button keycodes +
   headset-mic recording with signal. Any failure: dump `dmesg`,
   regmap LEVEL/MASK/STATUS bytes, and the parent IRQ count delta.

If jack detection still fails after the LEVEL fix: the next suspects are
(a) MBHC floor/bias wiring in the codec (register-level vs downstream dump),
(b) the MIC BIAS2/Headset-Mic DAPM route (deliberately not added while
detection was unreliable — revisit NOW if detection works).

## Phase 2 — cellular calls M0 (registration on the shipping image)

With the same kernel (ESP modules now present):
1. Boot pmOS from SD; confirm modules: `modprobe xfrm_user; modprobe
   esp6; modprobe esp4` (or check they autoload).
2. joan-imsd first-boot identity: run the packaged ISIM read path, then
   `joan-ims register` live on T-Mobile (81voltd IMS PDN + WDS TLV 0x2E
   P-CSCF + REGISTER 200 — all proven 2026-08-26).
3. Capture: SIP exchange + ESP SAs + `ip xfrm state` — evidence for M1.
4. Port from LOS alpha13 (test-covered): expiry refresh, P-CSCF failover,
   inbound CANCEL, OPTIONS — these are joan-imsd Python changes, doable
   offline against the captured evidence.

## Phase 3 — suspend ladder (same kernel, opportunistic)

1. `/sys/power/pm_test` now exists (PM_DEBUG=y). Ladder: devices → platform
   → processors → real mem, waking with power key each round, logging
   `PM: Some devices failed to suspend` names + wakeup_sources deltas.
2. If `echo mem` fails before any device callback → TZ lacks SYSTEM_SUSPEND
   → port the downstream-style suspend_ops (design already RE'd, see
   2026-09-11-suspend-resume-report.md).

## Phase 4 — cellular M1/M2 (after M0 evidence)

1. MT ring: stable GUA on the IMS iface, answer P-CSCF ESP keepalives
   (they were being dropped), TCP-in-xfrm if the carrier criterion says TCP.
2. Two-way voice: RTP receive + jitter buffer + G.711 loop wired to
   PipeWire (uplink via the echo-cancel source) — the principal new code.
3. Dialer glue: D-Bus on joan-imsd.

## Parallel, no bench needed (Fulgor)

- camss DT node (authorable now, probe needs bench)
- input-boost daemon + lock-gated scale daemon (ship in device package)
- haptics port (leds-qpnp-haptics + captured LRA params)
- wcd934x first-PR draft for upstream review

## Bench checklist reminders

- `sudo` not `doas` on this image; session tools as user, root only for
  regmap/dmesg/evtest
- RAM boot: `sudo -n fastboot boot <img>`; USB-C: plug/unplug testing doubles
  as the USB investigation's hands-on part when the report lands
- sticky SLIM TX bits cleared before every capture
- jack controls are iface=CARD (query by numid)
