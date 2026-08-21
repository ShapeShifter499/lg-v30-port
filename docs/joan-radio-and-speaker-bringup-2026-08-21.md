# joan — speaker amp, Wi-Fi and Bluetooth brought up

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-08-21

Kernel `0c0124a30` on both `joan/latest-clean-test` and `master`.

## 1. TFA9872 loudspeaker amplifier — probes and joins the card

joan's speaker amp is an NXP TFA9872 on BLSP2 QUP1 at 0x34, fed by **tertiary**
MI2S. Found the way the ES9218P should have been found the first time -- by the
dai-link that names the codec:

```
.name          = LPASS_BE_TERT_MI2S_RX,
.cpu_dai_name  = "msm-dai-q6-mi2s.2",
.codec_name    = "tfa98xx.7-0034",
```

So joan is **headphones on quaternary, speaker on tertiary**. The tertiary MI2S
machine-driver support added earlier for the DAC turned out to be what the
speaker needed.

Supported by extending mainline's `tfa989x` rather than writing a new driver.
Revision matching works out cleanly: the vendor dispatches on the full 16-bit
revision (0x1a72/0x2a72/0x1b72/0x2b72/0x3b72) while `tfa989x` masks to the low
byte, so a single `0x72` covers every die.

Two things had to be handled:

- **Different unlock.** Key 1 is at 0x0f, not `TFA989X_HIDE_UNHIDE_KEY` (0x40),
  and there is a second challenge-response key: read 0xfb, xor 0x005a, write
  0xa0. Miss either and the init writes are silently dropped.
- **Repurposed low registers.** The probe failed `-EIO` because `writeable_reg`
  rejects everything at or below `TFA989X_REVISIONNUMBER`. That is right for the
  older parts, but the 9872 reuses them -- the vendor table writes 0x02, and the
  "oscillator off" step targets bit 4 of **0x01**. Added a `low_regs_writeable`
  flag on `struct tfa989x_rev` selecting a permissive regmap.

Verified: `/sys/bus/i2c/drivers/tfa989x/` lists `2-0034`, the only remaining
message is the harmless dummy-regulator note, and the codec joins the sound card
where its CHSA control appears as **`Amp Input`**. `TERT_MI2S_RX Audio Mixer
MultiMedia1` is present.

**Not yet heard.** The software path is complete but nobody has listened to the
speaker. Note the CoolFlux DSP is bypassed, so there is no excursion or thermal
protection -- keep the gain conservative until the vendor container is loaded.

## 2. Wi-Fi — WORKING, scans real networks

Not a kernel bug. Three things were needed:

1. **`CONFIG_ATH10K_DEBUG` / `ATH10K_DEBUGFS` off.** These were `=y` and are the
   known WLAN breaker from the August investigation. Confirmed in the working
   boot: `ath10k_snoc: kconfig debug 0 debugfs 0 tracing 0`.
2. **Modem firmware**, which was on no build host. It lives on the device's own
   partition:
   ```sh
   mount -o ro /dev/disk/by-partlabel/modem /mnt/modemfw
   cp /mnt/modemfw/image/mba.mbn /mnt/modemfw/image/modem.* \
      /lib/firmware/qcom/msm8998/joan/
   echo start > /sys/class/remoteproc/remoteproc0/state
   ```
   WCN3990's WLAN firmware runs on the modem subsystem, so the modem must be up.
3. **`tqftpserv` + `rmtfs -r -P -s`** (from `joanfw.tgz`; rmtfs is already on the
   rootfs).

`wlan0` appears about 10 s after rmtfs starts. `nmcli dev wifi list` returns
real networks. The firmware reports itself correctly:

```
ath10k_snoc 18800000.wifi: wcn3990 hw1.0 target 0x00000008
ath10k_snoc 18800000.wifi: firmware ver api 5 features wowlan,mgmt-tx-by-reference,non-bmi
```

One cosmetic issue: `invalid MAC address; choosing random` -- the MAC is not
being read from NV.

## 3. Bluetooth — hci0 present

Kernel side was already complete (`BT_QCA`, `BT_HCIUART` + SERDEV + H4, DT node
with all four supplies, and `joan/bt-uart-clock-fix` already merged). What was
missing was firmware. Installing the two blobs from the firmware package is
enough:

```sh
install -m644 crbtfw21.tlv crnv21.bin /lib/firmware/qca/
```

`hci0` then exists. Not yet exercised beyond that.

## Rig notes

- **`echo b > /proc/sysrq-trigger` is far more reliable than `reboot`** from this
  rootfs for getting back to Android: adb up in 1 s, Android booted in 11 s.
  Plain `reboot` repeatedly failed to take and left the phone in pmOS.
- Long `sudo sh -c` blocks over ssh can hang on `echo start > .../state`; wrap
  the write in `timeout` so the session returns.
- busybox `ip` has no `-br`; there is no `iw`, but `nmcli` and `wpa_supplicant`
  are present.
- Everything installed to `/lib/firmware` persists -- the rootfs is the SD card,
  not the RAM boot.
