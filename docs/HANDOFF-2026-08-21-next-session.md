# joan — start here (handoff, 2026-08-21)

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-08-21

## One-line state

**Audio works** (stereo, headphones, through the ES9218P Quad DAC), **Wi-Fi
works**, **Bluetooth reaches hci0**, the **loudspeaker plays** (TFA9872 fixed
2026-08-22), and **SLIMbus playback works** (WCD9340 HPHL/HPHR audible at the
jack).  The **earpiece is still silent** and is the open audio item.

See `2026-08-22-tfa9872-fix-and-slimbus-playback.md` for both fixes, the
TFA9872 register map, and the traps.  That document also supersedes the
"sound does not play over SLIMbus / silent SoC reset" conclusion in
`aurel-handoff-2026-08-18-audio.md`, which no longer reproduces.

## Where everything is

| what | where |
|---|---|
| kernel | `ShapeShifter499/linux-lg-v30-joan` — `joan/latest-clean-test` **and** `master` both at `ca2f77f89` |
| port docs | `ShapeShifter499/lg-v30-port` — `abd7a21` |
| pmOS packages | `ShapeShifter499/lg-v30-joan-pmos-packages` (public) — UCM profile + firmware |
| working image | nest `~/joan-images/boot-joan-qmidbg35a.img` |
| build dir | skyforge `/data/buildcache/kbuild/build-adsp-only` |
| detail | `docs/joan-radio-and-speaker-bringup-2026-08-21.md`, `docs/NEXT-SESSION.md` |

Build: `make ARCH=arm64 O=/data/buildcache/kbuild/build-adsp-only
CROSS_COMPILE="ccache aarch64-linux-gnu-" -j12 Image.gz dtbs`, then
`cat Image.gz <joan dtb> > Image.gz-dtb` and repack on nest.

## The port map — settle this before touching audio

```
q6 DSP --QUATERNARY MI2S--> ES9218P  --> headphone jack     (works)
q6 DSP --TERTIARY   MI2S--> TFA9872  --> loudspeaker        (WORKS)
q6 DSP --SLIMbus--> WCD9340 --> HPHL/HPHR --> headphone jack (WORKS)
q6 DSP --SLIMbus--> WCD9340 --> EAR/LINEOUT --> jack too (NOT the earpiece)
```

**Find a codec's port from the dai-link that NAMES it**, never by inferring from
a neighbouring DT node. Getting that backwards cost about four boots.

## Next actions, in order

1. **DONE (2026-08-22): the speaker plays.**  Route
   `TERT_MI2S_RX Audio Mixer MultiMedia1` on and play; the driver now brings the
   amplifier up by itself.  **Keep the gain low** — the TFA9872 has no CoolFlux
   DSP at all (it is a Probus part), so there is no excursion or thermal
   protection and it is physically possible to damage the speaker.  There is
   also no amplifier gain control yet; level must come from the source until
   `TDMSPKG` is exposed as an ALSA control.
2. **UCM `SectionDevice` for the speaker** in `lg-v30-joan-pmos-packages`, so
   PipeWire exposes it alongside the headphone device.
3. **TFA firmware container** from the device's own partition, for protection +
   real loudness (see below).
4. **Cellular**: LTE registration WORKS as of 2026-08-22 — see
   `2026-08-22-cellular-bringup.md`.  Needed a missing `ipa_fws.mdt` (from the
   device's own modem partition) placed in the **initramfs**, and
   `CONFIG_RMNET=y`.  A real mainline bug was found and fixed on the way
   (`ca2f77f89`: unbounded GSI quiesce ahead of the version check).

   **Data is still blocked**, and the hardware error is now decoded: GSI
   reports `GSI_OUT_OF_BUFFERS_ERR` on channel stop, i.e. **the event ring is
   full**.  Prime suspect is the early return in `gsi_evt_ring_update()` that
   skips the event ring doorbell.  Start there — the doc has the details, the
   ruled-out list, and the instrument traps that produced three wrong
   conclusions.  VoLTE and calls sit behind data (T-Mobile has no CS
   fallback).
5. Then: tethering, cameras, USB-C.

## Recipes that work (do not re-derive)

**Wi-Fi** — needs all four:
```sh
# 1. kernel: CONFIG_ATH10K_DEBUG=n and ATH10K_DEBUGFS=n  (the known breaker)
#    verify in dmesg: "kconfig debug 0 debugfs 0"
# 2. modem firmware lives on the DEVICE, not any build host:
mount -o ro /dev/disk/by-partlabel/modem /mnt/modemfw
cp /mnt/modemfw/image/mba.mbn /mnt/modemfw/image/modem.* /lib/firmware/qcom/msm8998/joan/
# 3. the modem must be UP — WCN3990's WLAN firmware runs on it:
echo start > /sys/class/remoteproc/remoteproc0/state
# 4. userspace (tqftpserv from nest joanfw.tgz; rmtfs is already on the rootfs):
LD_LIBRARY_PATH=/tmp/joanfw/bin /tmp/joanfw/bin/tqftpserv &
rmtfs -r -P -s &
# -> wlan0 in ~10 s.  nmcli dev wifi list  finds networks.
```

**Bluetooth** — kernel side is already complete; only firmware was missing:
```sh
install -m644 crbtfw21.tlv crnv21.bin /lib/firmware/qca/   # -> hci0
```

**ADSP / sound card**: firmware is already at
`/lib/firmware/qcom/msm8998/joan/`; `echo start > .../remoteproc1/state`, then
the card registers. Do it within `deferred_probe_timeout=300` of boot.

## Rig notes — these cost real time

- **`echo b > /proc/sysrq-trigger` to get back to Android.** Plain `reboot` from
  this rootfs repeatedly failed and left the phone stuck in pmOS needing a manual
  power cycle. sysrq: adb in 1 s, Android booted in 11 s.
- Wrap `echo start > .../remoteproc*/state` in `timeout` — it can hang the ssh
  session, which looks like the phone died when it is perfectly healthy.
- **Read DAPM state and codec registers only WHILE A TONE IS PLAYING.** Between
  plays you see the power-down state and it imitates a failed sequence.
- **`wpctl`/`systemctl --user` over plain ssh do not see the phosh session.** The
  rootfs is Alpine/OpenRC (no systemctl at all), and phosh's bus is at
  `/tmp/dbus-<random>`. An empty `wpctl status` over ssh means nothing — I
  reported UCM broken on that basis and was wrong.
- `pkill -f <pat>` inside a `sudo sh -c` whose own command line contains `<pat>`
  kills its own shell. Use a bracket pattern. Hit three times.
- `/lib/firmware` installs persist — the rootfs is the SD card, not the RAM boot.
- busybox `ip` has no `-br`; no `iw`; `nmcli` and `wpa_supplicant` are present.
- Volume: `Headphone Playback Volume` 255 is 0 dB and painfully loud. Keep <= 210.

## Diagnostics worth reaching for first

- **ES9218P `DPLL_NUMBER` (regs 0x42-0x45), read while playing.** `0x00000000`
  means the DAC sees no input clock at all — that one register would have caught
  the wrong-port mistake in a single boot.
- **Play duration vs file duration.** A 6 s file returning in 2-3 s is underrun,
  no instrumentation needed.
- The image carries a debug stack (`apr.apr_dbg=1`, `apr.apr_hb_ms=10`, DAPM and
  glink breadcrumbs). Useful, but this is not a daily-driver build.

## Open / unproven

- Earpiece: NOT driven by the WCD9340.  Every analog output (EAR, HPHL/HPHR,
  LINEOUT1) was driven alone with the others confirmed off by register readback;
  all are audible only at the headphone jack and silent with nothing inserted.
  Do not re-run the mixer permutations — see the 2026-08-22 doc for the table.
  Open question is hardware: what the earpiece is physically connected to.
- TFA runs with no speaker protection: the part has no DSP, and SpeakerBoost for
  Probus parts runs as a module in the Qualcomm ADSP firmware
  (`AFE_MODULE_ID_TFADSP 0x1000B910`, param `0x1000B921`, on the tertiary MI2S
  port).  Reverse-engineerable: container format is defined in the vendor
  headers we have, the blob is on the device, and the algorithm is likely
  already inside the ADSP image we load.  Needs new q6afe plumbing.
- Wi-Fi MAC: `invalid MAC address; choosing random` (not read from NV).
- One vendor TFA register write is intentionally dropped; see the driver comment.
- Wi-Fi/BT/modem bring-up is all manual — nothing starts at boot.
