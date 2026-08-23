# joan — start here (handoff, 2026-08-22)

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-08-22

Supersedes `HANDOFF-2026-08-21-next-session.md` for audio and cellular.  That
document is still correct for Wi-Fi, Bluetooth and the ADSP recipes.

## One-line state

**The loudspeaker plays, SLIMbus playback works, speaker volume is
controllable, and the modem registers on T-Mobile LTE.**  Cellular **data does
not flow**; the cause is decoded down to a GSI event ring that fills and never
drains.  The **earpiece does not work** and is not on the WCD9340 at all.

## Where everything is

| what | where |
|---|---|
| kernel | `ShapeShifter499/linux-lg-v30-joan` — `master` **and** `joan/latest-clean-test` at `ca2f77f89` |
| kernel worktree | skyforge `~/vibe-coding-projects/coding/linux-mainline-v30-usb-otg` (branch `joan/usb3-otg-bringup`) |
| port docs | `ShapeShifter499/lg-v30-port` — branch `aurel/card94-reset-script` at `cc1bcbc` (note: **not** master; master is behind, a pre-existing divergence) |
| pmOS packages | `ShapeShifter499/lg-v30-joan-pmos-packages` — `94bf241` |
| build dir | skyforge `/data/buildcache/kbuild/build-adsp-only` |
| boot images | nest `~/joan-images/` — most recent useful: `boot-joan-cell-ipa.img` (IPA fw in initramfs) |
| detail docs | `2026-08-22-tfa9872-fix-and-slimbus-playback.md`, `2026-08-22-cellular-bringup.md` |
| Deck | board 4 "Shared Tasks": **#102** cellular, **#99** audio, **#101** speaker volume (done) |

## Build and boot

```sh
# build (skyforge)
cd ~/vibe-coding-projects/coding/linux-mainline-v30-usb-otg
make ARCH=arm64 O=/data/buildcache/kbuild/build-adsp-only \
     CROSS_COMPILE="ccache aarch64-linux-gnu-" -j12 Image.gz dtbs
cat /data/buildcache/kbuild/build-adsp-only/arch/arm64/boot/Image.gz \
    /data/buildcache/kbuild/build-adsp-only/arch/arm64/boot/dts/qcom/msm8998-lge-joan.dtb \
    > /tmp/Image.gz-dtb
scp /tmp/Image.gz-dtb nym-nest-family:/tmp/joanunpack/Image.gz-dtb

# package + boot (nest).  ramdisk-ipa carries ipa_fws.* - see Cellular below.
ssh nym-nest-family
cd /tmp/joanunpack && mkbootimg --kernel Image.gz-dtb --ramdisk ramdisk-ipa \
  --base 0x00000000 --kernel_offset 0x00008000 --ramdisk_offset 0x02000000 \
  --tags_offset 0x00000100 --pagesize 4096 --cmdline "$(cat cmdline-pipes)" \
  --output ~/joan-images/boot-joan-test.img
adb reboot bootloader && fastboot boot ~/joan-images/boot-joan-test.img
sudo ip addr add 172.16.42.2/24 dev enp0s29u1u5 && sudo ip link set enp0s29u1u5 up
```

Phone shell: `/tmp/joan "<cmd>"` on nest (wrapper around
`sshpass -f /tmp/pmos-pass ssh user@172.16.42.1`).  `sudo` on the phone reads
the password from stdin: `cat /tmp/pmos-pass | /tmp/joan "sudo -S -p '' <cmd>"`.

`/tmp` on the phone is tmpfs — helper scripts do **not** survive a reboot.

## AUDIO

### Working

- **Loudspeaker** (TFA9872, tertiary MI2S).  Just route
  `TERT_MI2S_RX Audio Mixer MultiMedia1` on and play; the driver brings the
  amplifier up itself.
- **Headphone jack** (ES9218P, quaternary MI2S) — was already working.
- **SLIMbus playback** (WCD9340 → HPHL/HPHR → jack).  This contradicts
  `aurel-handoff-2026-08-18-audio.md`, which recorded that sound does not play
  over SLIMbus and that a silent SoC reset kills the stream.  Neither
  reproduces; that document is left untouched and referenced.
- **Speaker volume**: `Speaker Playback Volume`, 0-15.  `TDMSPKG` is an
  *attenuation* in hardware (0 = loudest), so the control is registered
  inverted.

### The TFA9872 lesson worth keeping

The part is an NXP **Probus** device with **no CoolFlux DSP** — its register map
has none of the DSP interface fields the TFA9912 map has.  mainline addressed it
with the older TFA1 offsets, and writes to unimplemented registers are ACKed on
the wire and silently dropped, so DAPM reported the amp powered and enabled
while the chip sat at power-on default.  Real locations: `PWDN`/`AMPE`/`DCA` in
reg `0x00`, `AUDFS` in `0x02` bits 3:0, status in `0x10`.  The amp is engaged by
the on-chip manager once `MANSCONF` (`0x01` bit 2) is set — **never** by writing
AMPE.

**No speaker protection exists.** Keep source levels low.  SpeakerBoost for
Probus parts runs as an ADSP firmware module (`AFE_MODULE_ID_TFADSP 0x1000B910`,
param `0x1000B921`, tertiary MI2S port) — reverse-engineerable, container format
is in the vendor headers, blob is on the device.

### Earpiece — negative result, do not re-run the mixer permutations

Every WCD analog output was driven alone with the others confirmed **off by
register readback**:

| output | headphones IN | headphones OUT |
|---|---|---|
| `EAR PA` (`ANA_EAR` = 0x80) | headphones | silent |
| `HPHL`/`HPHR` (`ANA_HPH` = 0xf0) | headphones | silent |
| `LINEOUT1` (`ANA_LO_1_2` = 0xbc) | headphones | silent |

All three reach only the headphone jack.  **joan's earpiece is not driven by the
WCD9340**, despite the vendor's own `handset` path terminating at `EAR PA`.
Flipping the board's analog switch (`pm8998_gpios 12`, exposed as
`Headphone Analog Switch`) changes nothing.  This is now a hardware-identification
question — schematic, teardown, or the Android HAL's device-to-backend map.

Note `RX INT0 DEM MUX` must be `CLSH_DSM_OUT`; `NORMAL_DSM_OUT` has no route
defined at all and silently breaks the chain.

## CELLULAR

### Working and verified

Registers on **T-Mobile LTE** (310/260), -57 dBm, CS+PS attached, SIM read,
ModemManager finds the modem, data bearer connects with a real IPv6 /64.
Stable — hours of uptime, zero modem crashes.

Two things were needed:

1. **`ipa_fws.mdt` must be in the initramfs.**  It lives on the device's own
   modem partition (`mount -o ro /dev/disk/by-partlabel/modem`, then
   `image/ipa_fws.*`; also `/system/etc/firmware/`).  IPA probes at ~1.4 s,
   long before the SD rootfs mounts, so a copy on the rootfs is found too late,
   the apps IPA driver never probes, and the modem asserts inside its own IPA
   init and crash-loops.  `ramdisk-ipa` on nest already has it.
2. **`CONFIG_RMNET=y`** (was `=m`).  No modules on the rootfs, so `=m` means
   absent, and without rmnet there is no data interface at all.

### Bring-up order (IPA first, then modem)

```sh
echo start > /sys/class/remoteproc/remoteproc0/state
LD_LIBRARY_PATH=/tmp/bin /tmp/bin/tqftpserv &     # from nest joanfw.tgz
rmtfs -r -P -s &
sleep 30                                          # core QMI services are late
qmicli -d qrtr://0 --dms-set-operating-mode=online # comes up 'shutting-down'
rc-service modemmanager restart                    # OpenRC supervises it - do
                                                   # NOT start a second instance
mmcli -m 0 --simple-connect="apn=fast.t-mobile.com,ip-type=ipv4v6"
```

Wait ~25-30 s after starting the modem: WDS/NAS/WMS/UIM register noticeably
later than the first batch of services.  `pd-mapper` is **not** needed.

### Data — blocked, with the error decoded

```
GSI command 2 for channel 5 timed out, state 4
channel 5 global error ee 0x00000000 code 0x00000002
error -11 attempting to stop endpoint 3     -> then an oops
```

Decoded against downstream `drivers/platform/msm/gsi/gsi.h`:

| value | meaning |
|---|---|
| code `0x2` | **`GSI_OUT_OF_BUFFERS_ERR`** |
| state `4` | `GSI_CHAN_STATE_STOP_IN_PROC` |

"Out of buffers" on a TX channel means **the event ring is full** — no free
entry for the hardware to post a completion into.  That accounts for every
symptom: completions never posted, GSI interrupt count frozen (15 on every
boot), transactions never complete, channel cannot be stopped.

The ring only drains when the AP rings the event ring doorbell, which happens
**only** at the end of `gsi_evt_ring_update()`, after IEOB drives NAPI.

**Prime suspect**, in `gsi_evt_ring_update()`:

```c
trans = gsi_event_trans(gsi, event);
if (!trans)
        return;            /* early return - doorbell NOT rung */
```

If that ever fires, the read pointer never advances and the ring is stranded
permanently.

#### Start here

1. Instrument `gsi_evt_ring_update()`: is it entered, and does it take that
   early return?  Use a **bounded counter**, not `net_ratelimited_function()`.
   (This instrumentation was written but never successfully booted.)
2. If IEOB genuinely never fires, read `CNTXT_SRC_IEOB_IRQ_MSK` and
   `CNTXT_TYPE_IRQ_MSK` back **from hardware** rather than trusting the write,
   and diff the event ring context programming against downstream `gsi.c`.
3. Separately, fix the oops on the `-EAGAIN` path — a failed channel stop
   should not crash the kernel.

#### Ruled out by inspection — do not re-check

- v3.1 GSI register definitions exist and are correctly selected
  (`reg/gsi_reg-v3.1.c`).
- The IPA driver supports this SoC: `qcom,msm8998-ipa` + `ipa_data-v3.1.c`.
- IEOB is enabled at channel start, and `GSI_IEOB = BIT(3)` is standard.
- `ipa_modem` has no `ndo_get_stats64`, so the sysfs counters are valid.
- Uplink aggregation is **not** the cause: a hand-created rmnet link (fresh
  aggregation defaults, count 1) behaves identically.
- The rmnet mux child is **mandatory** — `ipa_start_xmit()` requires
  `skb->protocol == ETH_P_MAP`.  It is not double-wrapping.

### Fixed on the way (`ca2f77f89`)

`__gsi_channel_stop()` ran an unbounded transaction quiesce *before* the check
that makes the call a no-op on pre-v4.0 hardware.  On IPA v3.1 that hung
`ipa_runtime_suspend()` forever with the device stuck in `RPM_SUSPENDING`,
after which every `pm_runtime_get()` in `ipa_start_xmit()` failed and all
uplink was dropped.  Verified fixed: IPA suspends and resumes normally, and
`ip link set rmnet_ipa0 down` succeeds where it hung three times out of three.

A **rejected** approach is recorded so it is not retried: holding a permanent
runtime PM reference (an earlier workaround) removes the deadlock but breaks
transmit, because `ipa_modem_wake_queue_work()` — the only external
`netif_wake_queue()` in the driver — is scheduled from the *resume* path.

### VoLTE and calls

Both sit behind working data.  A call attempt is refused with QMI error 90
`IncompatibleState`: the modem declining a circuit-switched call.  **T-Mobile
US has retired 2G/3G**, so there is no CS fallback and voice requires IMS.

The modem *does* carry an IMS stack — `qrtr-lookup` lists proprietary services
**700-707 and 800**.  libqmi implements none of them, so VoLTE is
reverse-engineering work, approved by Lance 2026-08-22.

Call audio is separately blocked: the earpiece does not work, so a connected
call would need loudspeaker or headphones.

## Instrument traps — read before trusting any measurement

These produced three successive wrong conclusions about the data path:

- **Logging only failure paths** makes "never called" indistinguishable from
  "called and succeeded".  Log entry unconditionally with a bounded budget.
- **`net_ratelimited_function()` silently drops** after ~10 messages per 5 s.
  An absent message means nothing.
- **The rmnet child and the IPA parent keep separate counters.**  Read both, or
  you will reason about one while watching the other.
- **`dmesg -c` destroys the boot log** you may need; the `apr.apr_hb_ms=10`
  heartbeat wraps an 8 MB buffer in ~20 minutes anyway.
- **ALSA numids shift** whenever a kcontrol is added or removed.  Always
  resolve controls **by name**; a stale numid silently configures a different
  control.
- **Userspace owns the card.**  `pipewire`/`wireplumber`/`pulseaudio` claim SLIM
  RX0 via UCM; `slim_rx_mux_put()` then logs "PORT is busy" and returns 0
  *without updating the value*, and the state cannot be cleared from userspace
  afterwards — it needs a reboot.  Kill the daemons before configuring.

## Rig notes

- `echo b > /proc/sysrq-trigger` to get back to Android.  Plain `reboot` wedges
  the phone.
- Wrap `echo start > .../remoteproc*/state` in `timeout` — it can hang the ssh
  session while the phone is perfectly healthy.
- Read DAPM state and codec registers **only while a tone is playing**.
- ModemManager is supervised by OpenRC.  Starting a second instance fails to
  acquire the D-Bus name and wedges `mmcli`; use `rc-service modemmanager
  restart`.
- `busybox ip` cannot show rmnet details or accept `nodad`.  Extract `sbin/ip`
  from Alpine's `iproute2-minimal` apk plus `libmnl.so.0` and run with
  `LD_LIBRARY_PATH`; a full `apk add` fails because optional libcap
  subpackages cannot be fetched (no internet on the phone).
- IPv6 DAD does not complete on the cellular link: `echo 0 >
  /proc/sys/net/ipv6/conf/<if>/accept_dad` **before** adding the address.
- Installed on the phone this session: `libgpiod`, `qrtr`, `qrtr-libs`,
  `qmi-utils`.
- `slim_qcom_ngd_ctrl.pgd_enable` must stay **0** (documented as hanging the
  controller); `joan_pipes` should stay **on** (its default).
