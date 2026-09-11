# joan audio + wake-path test — 2026-09-07 (Fulgor staging)

Boot image `boot-joan-pmos-audio-wake-20260907.img`
(kernel `joan/wake-path-v1` = fb968169503b + DPU TE-gate 2f1308c271d8,
ramdisk/cmdline carried verbatim from prealpha sdcard boot.img so the
existing SD rootfs boots unchanged).

image sha256: fdc0758d0c384cdf2eaf902c787df628f8dc7b45e7473cfc425c841923b1bbf2

## 0. Boot and prep

    # on nest, phone in fastboot (Vol-Up + plug USB, or `adb reboot bootloader`)
    sudo -n fastboot boot ~/joan-test-assets/audio-wake-20260907/boot-joan-pmos-audio-wake-20260907.img

The prealpha rootfs does NOT yet contain the new audio packages. After boot
(USB network 172.16.42.1, ssh user@172.16.42.1), push and install:

    scp alsa-ucm-conf-lge-joan-1.0-r4.apk device-lge-joan-1-r12.apk user@172.16.42.1:/tmp/
    ssh user@172.16.42.1 'sudo apk add --allow-untrusted /tmp/alsa-ucm-conf-lge-joan-1.0-r4.apk /tmp/device-lge-joan-1-r12.apk'

Then stop PipeWire's takeover of the card for step 1 (raw capture first):

    systemctl --user stop pipewire wireplumber  (or kill both)

## 1. Raw capture — before anything clever

    amixer -c0 cset name='TX COPP Topology' None      # neutralise step 3 first
    alsaucm -c 0 set _verb HiFi set _enadev Mic
    arecord -D hw:0,1 -f S16_LE -r 48000 -c 1 -d 5 /tmp/mic.wav

Repeat for `Headset` (1ch) and `DualMic` (2ch). If these fail, nothing else
matters. NOTE: the UCM devices set the topology per LG calibration
(SM_ECNS/DM_Fluence) — if a mic is SILENT here, retry after setting
Topology None before blaming routing.

## 2. MBHC — jack + in-line buttons (4-pole headset, 3-button remote)

Plug/unplug: expect insert/remove events on the jack input device (evtest).
Buttons must decode distinctly: KEY_PLAYPAUSE / KEY_VOICECOMMAND /
KEY_VOLUMEUP / KEY_VOLUMEDOWN. All-PLAYPAUSE = threshold ladder did not
take. If jack IRQ still dead after the gnd_swh fix: hypothesis spent, next
look is interrupt plumbing (do not chase further this session).

## 3. ADSP topology — the risky one

    amixer -c0 cset name='TX COPP Topology' DM_Fluence
    arecord ... (as step 1, DualMic)

Can fail CLOSED (silent input, not just unprocessed) if the ADSP rejects
the topology. Recovery is always: cset 'TX COPP Topology' None.

## 4. Wake-path — blank/unblank rainbow check

Lock/unlock or blank/unblank the display repeatedly (phosh). Before the
TE-gate, the first frame after unblank could tear ("rainbow"). After:
clean. If dynamic debug is on, `dmesg | grep -i "gated on TE"` shows the
new path firing; absence of the message is not a failure (DPU_DEBUG).

## Optional evidence

- Micbias readback by register, NOT by echoing the ALSA control back.
- H932 twin: device-lge-joan-h932-1-r8.apk staged alongside.

Artifacts on nest: ~/joan-test-assets/audio-wake-20260907/
(boot img, 4 apks, SHA256SUMS, this protocol).

## Access-lane addenda (2026-09-11, from Ember's bench memory)

- The USB gadget dies ~63 s into every pmOS boot because `usb-signaller`
  applies default_mode=charging_only. Mask it with ZERO rootfs writes:
  `fastboot boot <img> --cmdline "panic=5 pmos.force-partition-resize
  pmos_rootfsopts=defaults systemd.mask=usb-signaller.service"`.
  sshd then answers at ~+81 s. Password via **sudo**, not doas, on this image.
- To read the pmOS rootfs from LineageOS without recovery (vold holds the
  device, but losetup does not take O_EXCL):
  `losetup -r -f /dev/block/mmcblk0p2 && mount -o ro,noload -t ext4
  /dev/block/loopN /mnt/pmroot`. Read-only; supersedes the ext4 feature-bit
  dd surgery for read access (surgery still needed for writes from recovery).
- Reboot hazards: never `setprop ctl.stop vold` / `stop vold` from LOS (reboots
  phone); never `udevadm trigger --action=add` inside pmOS (resets this SoC).
- Before every capture measurement: clear every `AIF*_CAP Mixer SLIM TX*`
  bit (sticky state across uptime makes the ADSP reject multi-channel TX;
  one port = clean start).
- STANDING APPROVAL (Lance): always look at the code and reverse engineer
  stock ROM/kernel wherever it helps the port — state this in every joan
  handoff and note.
