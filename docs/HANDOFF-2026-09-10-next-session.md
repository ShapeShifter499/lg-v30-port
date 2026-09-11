# Handoff: joan audio bench — 2026-09-10 (Ember → next session)

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-09-10

Supersedes `HANDOFF-2026-09-08-next-session.md` (Fulgor). Read this first.

> **Partially superseded, same day, by
> `2026-09-10b-capture-silence-isolated-to-slim-tx.md`.** Sections 1-5 (bench
> access, usb-signaller, the missing modules, load order, the SD read trick and
> the UCM ordering trap) all still hold. **Section 6's diagnosis does not.**
> The SLIM capture BE *does* start and the front end *does* power up; the
> `arecord` hw_params failure was a channel-count problem, and `out 0` merely
> meant no capture was running at the time the dump was taken. Read the newer
> note before acting on §6.

## Headline

Three blockers found and fixed; the capture chain now runs end to end for the
first time on this port. **`arecord` produces well-formed 5 s WAVs — and they
are digital silence (all zeros).** The remaining defect is isolated to one
place: the SLIMbus capture backend never starts, so the codec's TX path stays
unpowered and the ADSP reads an idle AFE port.

Nothing was written to the SD card this session. Every fix below is applied at
boot time or in tmpfs.

## Where the phone is RIGHT NOW

US998 on the bench. It was left running a RAM-booted pmOS (v2 label image,
kernel `2f1308c271d8`) with a **stable USB gadget and working ssh**. If it has
since been power-cycled it will be back in LineageOS, which is fine — the whole
sequence below is hands-free from LOS via adb.

## 1. The USB gadget teardown — SOLVED

Fulgor's "+56 s gadget death, suspect usb-moded" was `usb-signaller`. The
phone's own journal (pulled read-only, see §4):

    [62.485] Started usb-signaller.
    [63.209] Parsing configuration file: /usr/lib/usb-signaller/usb-signaller.toml
    [63.211] Applying default mode: charging_only
    [63.211] Setting mode of UDC a800000.usb from Developer to Charging
    [63.557] UDC reconfigured:  Enabled: false  Mode: Charging

`postmarketos-ui-phosh` depends on `postmarketos-usb-moded`, whose
`-default-profile-charging` subpackage writes
`/usr/lib/usb-signaller/usb-signaller.toml` = `default_mode="charging_only"`.
`usb-signaller.service` is enabled in `basic.target.wants`, so it runs early and
disables the UDC the initramfs brought up as NCM.

**Fix used (zero writes):** mask it on the kernel command line.

    sudo -n fastboot boot <img> --cmdline \
      "panic=5 pmos.force-partition-resize pmos_rootfsopts=defaults systemd.mask=usb-signaller.service"

That base cmdline is the v2 image's own (read out of the boot header); the
bootloader appends its `androidboot.*` params on top. Verified: gadget survives
indefinitely, `systemctl is-enabled usb-signaller` → `masked-runtime`.

**Permanent fix, NOT applied (needs a rootfs write, ask Lance):** set
`default_mode="developer_mode"` in that toml, or install
`postmarketos-usb-moded-default-profile-developer`.

### sshd was never broken
It is enabled in `multi-user.target.wants` and simply came up *after* the
teardown. With the mask it answers at **+81 s**. Do not go hunting sshd.

## 2. The kernel had no modules — the reason audio never worked

This is the big one. It invalidated the premise of several prior sessions.

    uname -r      = 7.2.0-rc2-g2f1308c271d8      (RAM-booted kernel)
    /lib/modules/ = 7.2.0-rc2                    (only this, on the SD)
    modprobe qcom_q6v5_pas
      -> FATAL: Module not found in directory /lib/modules/7.2.0-rc2-g2f1308c271d8

`lsmod` was empty. Every audio driver is `=m` (`QCOM_Q6V5_PAS`, `QCOM_APR`,
`SND_SOC_WCD934X`, `SND_SOC_TFA989X`, `SND_SOC_ES9218P`) and
`CONFIG_LOCALVERSION_AUTO=y` appends the git hash to `uname -r`. In the build
tree only `Image.gz` had ever been made — `make modules` was never run, so
`qcom_q6v5_pas.ko` did not exist anywhere.

Consequence: no ADSP remoteproc → no APR → no ASoC card. `/proc/asound/cards`
did not exist. **Every earlier mic test was aimed at a card that was not there.**

Modules are now built from the identical tree and toolchain
(`aarch64-linux-gnu-gcc` 16.1.0, no ccache prefix, `.config` untouched so the
Image stays byte-identical). Tarball, 28 MB, stripped:

    ~/.ember/workspace/joan-audio-2026-09-10/joan-modules.tgz

Staged into tmpfs and bind-mounted over `/lib/modules` — **no SD writes**:

    tar xzf /tmp/joan-modules.tgz -C /tmp/modstage
    mount --bind /tmp/modstage/lib/modules /lib/modules

### Durable fix worth doing
Build the audio stack `=y` so a `fastboot boot` image is self-contained and
carries no rootfs dependency. That is the right shape for this bench workflow.

## 3. Module load order — two hard-won rules

- **NEVER `udevadm trigger --action=add`.** A mass re-probe on this SoC reboots
  the phone. Cost one cycle to learn. Load modules explicitly instead.
- **SLIMbus is required and easy to miss.** Without it the card never appears
  and `/sys/kernel/debug/devices_deferred` reads exactly:

      sound	msm-snd-sdm845: SLIM Playback: codec dai not found

  Load `slimbus`, `regmap-slimbus`, `slim-qcom-ngd-ctrl` and the deferred list
  empties and the card registers:

      0 [LGV30          ]: sdm845 - LG-V30

Working order (all survive; ADSP reaches `state=running`):

    qcom_q6v5_pas
    apr
    q6core snd-q6dsp-common q6afe q6afe-dai q6asm q6asm-dai q6adm q6routing
    wcd934x snd-soc-wcd934x snd-soc-tfa989x snd-soc-es9218p
    slimbus regmap-slimbus slim-qcom-ngd-ctrl
    snd-soc-qcom-common snd-soc-sdm845

## 4. Reading the SD without recovery and without superblock surgery

vold holds `mmcblk0p2` with an exclusive open, so `mount` returns EBUSY from
LOS. `losetup` does **not** take `O_EXCL`:

    losetup -r -f /dev/block/mmcblk0p2
    mount -o ro,noload -t ext4 /dev/block/loopN /mnt/pmroot

Read-only, no recovery, no `dd` on the superblock, no hands. This is how the
journal in §1 was obtained. Script: `scripts/bench-automation/`.

Also confirmed: **`setprop ctl.stop vold` reboots the phone** — vold is critical
on this build. Do not try to free the device that way.

## 5. The UCM ordering trap — must-know

The UCM `EnableSequence` for every capture device sets
`cset "name='TX COPP Topology' SM_ECNS"`. That topology makes the ADSP reject
the COPP open:

    qcom-q6adm: cmd = 0x10326 return error = 0x1     (ADM_CMD_DEVICE_OPEN_V5, ADSP_EFAILED)
    q6asm-dai: q6asm_dai_prepare: stream reg failed ret:-22
    arecord: set_params:1462: Unable to install hw params

**Set `TX COPP Topology` to `None` AFTER `alsaucm ... _enadev`, never before.**
The old protocol had it before, so UCM overwrote it and capture always failed.
Correct sequence:

    alsaucm -c 0 set _verb HiFi set _enadev Mic
    amixer -c0 cset name='TX COPP Topology' None
    arecord -D hw:0,1 -f S16_LE -r 48000 -c 1 -d 5 /tmp/Mic.wav

`hw:0,1` is MultiMedia2 and is correct — it is what the UCM's `CapturePCM`
names. `hw:0,0` returns "Invalid argument".

## 6. Where it stands: capture runs, output is silence

With all of the above, `arecord` succeeds and writes correct WAVs:

    Mic.wav      240000 frames, 1ch, 48000Hz   RMS 0.0   peak 0   nonzero 0.0%
    Headset.wav  240000 frames, 1ch, 48000Hz   RMS 0.0   peak 0   nonzero 0.0%
    DualMic.wav  240000 frames, 2ch, 48000Hz   RMS 0.0   peak 0   nonzero 0.0%

Pure zeros, not noise floor. WAVs and mixer dumps in
`~/.ember/workspace/joan-audio-2026-09-10/`.

### The isolated defect

The routing kcontrols all take (verified by readback, not by echo):

    MultiMedia2 Mixer SLIMBUS_0_TX = on      AIF1_CAP Mixer SLIM TX6 = on
    CDC_IF TX6 MUX = 2 (DEC6)                ADC MUX6 = 1 (AMIC)
    AMIC MUX6 = 1 (ADC1)                     DEC6 Volume = 84   ADC1 Volume = 12

But during an active capture **nothing in the codec powers up**:

    MIC BIAS1: Off  in 0 out 0
    AMIC1:     Off  in 1 out 0
    ADC1:      Off  in 1 out 0
    SLIM TX6:  Off  in 1 out 0
    AIF1 CAP:      Off  in 5 out 0
    AIF1 Capture:  Off  in 5 out 0

No widget is `On` in either the codec or the q6routing component. `out 0` on
every one: the path has sources but no route to an active sink. The DPCM
backend (`SLIMBUS_0_TX` ↔ `wcd9340 1`) is not being started, so the ADSP pulls
an idle AFE port and hands back the zero-filled buffers it was given.

Gains are not the cause: `DEC6 Volume` 84/124 is 0 dB and `ADC1 Volume` is
12/20.

### Two hypotheses already RULED OUT — do not re-walk these

1. **"The SLIM capture BE is missing from DT."** No. `slim-capture-dai-link`
   exists at `msm8998-lge-joan.dts:1392`, `q6afedai SLIMBUS_0_TX` ↔
   `wcd9340 1`, with `q6routing` as platform.
2. **"`sdm845_dai_init`'s `slim_port_setup` latch means only the playback DAI
   gets a channel map."** No. `wcd934x_set_channel_map()` writes to the
   codec-global `wcd->tx_chs[]` / `wcd->rx_chs[]`, not per-DAI, so the single
   call from the first SLIM link populates the capture channels too.

### Suggested next move

Instrument why DPCM does not select/start the BE for FE MultiMedia2 — the
`dpcm_path_get` / `dpcm_be_dai_startup` path in `soc-pcm.c`, with
`snd_soc_dapm` debug on. The question to answer is why the q6routing mixer
being `on` does not yield a powered path from the FE widget to the
`SLIMBUS_0_TX` BE DAI widget. Compare against a working sdm845 board (db845c)
which uses the same machine driver and the same mixer names.

## Access lanes (all exercised this session, all hands-free from LOS)

    adb reboot bootloader
    sudo -n fastboot boot <img> --cmdline "<base> systemd.mask=usb-signaller.service"
    # nest side, needs sudo:
    sudo ip link set <iface> up; sudo ip addr add 172.16.42.2/24 dev <iface>
    sshpass -p 147147 ssh user@172.16.42.1

`doas` does **not** exist on this image — it is `sudo`, and `user` is in
`wheel` and `audio`. Non-interactive: `printf '%s\n' 147147 | sudo -S <cmd>`.
`147147` is postmarketOS's stock default from pmbootstrap, not a secret — it is
recorded here so the next session does not have to go looking. The scripts in
`scripts/bench-automation/` read it from `$JOAN_PW` so it is not duplicated in
source.

Automation that drives all of this from the nest, including live `dmesg` and
heartbeat channels that survive a SoC reset, is in
`scripts/bench-automation/`.

## Repo state

- kernel `linux-mainline-v30` @ `2f1308c271d8` — unchanged, `.config`
  unchanged, Image byte-identical. Modules built in-tree (untracked artifacts).
- `lg-v30-port` — this handoff + `scripts/bench-automation/`. Staged, NOT pushed.
- Nothing was written to the SD card at any point this session.

## House rules (unchanged)

Trailers `Signed-off-by: Lance <Gero3977@gmail.com>` + `Assisted-by:
<harness>:<model>`; never `Co-Authored-By: Claude`. Stage, don't push. SD-card
path only; never flash during qualification. Do not point IPA DMA at guessed
addresses.
