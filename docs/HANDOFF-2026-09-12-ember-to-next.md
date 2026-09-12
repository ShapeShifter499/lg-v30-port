# Handoff: joan — 2026-09-12 (Ember -> next session)

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-09-12

STANDING APPROVAL (Lance): always look at the code and reverse engineer stock
ROM/kernel wherever it helps the port. Standing goal: the port should FEEL like
the software was made for the device.

## Read first

`docs/2026-09-12-boot-lottery-root-cause-and-slowness.md` — the three findings
of this session with their evidence. This file is only the state and the queue.

## Phone state at handoff

US998, SD-card pmOS, RAM-booted from
`~/joan-test-assets/r16-20260912/boot-joan-pmos-r16-soundwire-irq20-20260912.img`
(sha256 680be63f…) on nest. Kernel 7.2.0-rc2 = `ff98974a67aa`.

- **Jack detect is ARMED on a first boot** — no lottery. soundwire on hwirq 20,
  all seven MBHC handlers registered, `mbhc sw intr` firing.
- `slim` reads **Level**, register `0461 = 01` with `MASK0 = f2`.
- The r16 *modules* on the rootfs were installed by hand (only the two changed
  `.ko`s + depmod), because the full apk upgrade cannot fit in `/boot` — see
  "Packaging" below. The rest of `/lib/modules` is still r14, which is fine:
  r14 and r16 differ only in those two source files and share vermagic.
- nest side needs `sudo ip link set enp0s29u1u5 up` + `ip addr add
  172.16.42.2/24` after **every** boot before ssh to 172.16.42.1 works.
  The phone's gadget is `1d6b:0104` "LG V30 / lge-joan" — NOT an `18d1:`/`1004:`
  id, so a `lsusb | grep 18d1` style check reports "phone absent" wrongly.
- tuned profile was restored to its original `throughput-performance` after the
  A/B. It is the wrong profile (see below) but I did not change it persistently.

## !! Phone is WEDGED at handoff — needs a physical force-off

I restarted `81voltd` on the live bench to test the startup-race hypothesis
below. The USB gadget dropped immediately (device number 34 -> 40) and pmOS
stopped answering: no IPv4, no IPv6 neighbour, no reply to `ff02::1`, and
link-local ssh times out. The gadget still *enumerates* as
`1d6b:0104 LG V30 / lge-joan`, so the device is powered and configfs is up,
but nothing above the USB layer responds.

Nothing persistent is at risk — it is a RAM boot and the SD rootfs was not
being written at the time. **Recovery is the documented one: force-off (power
~10 s) -> normal power-on -> LineageOS.** It cannot be done remotely; there is
no adb (that is LOS's) and no ssh.

**Lesson, and it is mine:** `81voltd` speaks QMI over QRTR to the modem, which
shares the SoC with the IPA/rmnet path that carries the USB network. Bouncing
it under a live session took the bench link down with it. The ordering fix
belongs in the unit file and must be tested across a *clean boot*, not by
restarting the service on a running bench.

## What is DONE and verified

1. **Boot lottery — root-caused and fixed.** joan's DTS aimed the soundwire
   controller at `<&wcd9340 8>` = `WCD934X_IRQ_MBHC_SW_DET`. Unshared line,
   two claimants, probe order decided the winner. Now 20, matching
   `sdm845-wcd9340.dtsi`. Verified first boot, twice.
2. **wcd934x LEVEL fix** moved into the regmap-irq type table + codec requests
   `IRQF_TRIGGER_HIGH`. Verified at the register, with `MASK0=f2` proving the
   bit survives children enabling interrupts.
3. **msm8998 CAMSS DT node authored** (`joan/camss-msm8998-dt`, `110f579bd5ac`).
   Compile-tested, `status = "disabled"`, never probed.

## Queue — ordered

1. **Headset test (needs a person).** The phone is in exactly the right state:
   MBHC armed. Plug/unplug a 4-pole headset, press the remote button x3,
   unplug. Watch `/proc/interrupts` lines 139-143 for growth and read
   `/dev/input/*` for the jack switch + keycodes. This is the last Phase 1 item
   and it has been blocked on a clean boot for several sessions — it is no
   longer blocked.
2. **IMS M0.** Modem is registered on T-Mobile 310260, LTE, 88%, packet service
   attached. `81voltd`/`rmtfs`/ModemManager all active. Blocked on: **the IMS
   PDN is not up** — bearers 1/2/3 are APN `pwg`, all disconnected; only
   bearer 0 (`fast.t-mobile.com`) is connected, and `rmnet_ipa0` carries only
   a link-local address, no `2607:` GUA. `81voltd`'s journal is empty.
   Two defects to fix in `joan_ims_live.py` regardless:
   - bearer index is hardcoded (`mmcli -b 2`); it must *find* the IMS bearer.
   - the parsed interface name is passed to `subprocess` unchecked, so an
     absent bearer dies as `TypeError: expected str ... not NoneType` instead
     of "IMS bearer not up". Fail closed with a real message.
   Lance has approved dialling **his own Google Voice number** for call tests
   once registration succeeds. Do not dial before a 200 OK to REGISTER.
3. **Slowness: change the power profile.** PPD `performance` -> tuned
   `throughput-performance` is a server profile and is the single cause of the
   4 MB readahead, `swappiness=10` (5.2 GB of zram stranded at 0 used) and
   40%/10% dirty ratios. Measured ~20% faster on small random reads under
   `balanced`. Decide whether to pin `balanced` in the device package, and
   benchmark the *write* side, which is the part still unmeasured.
4. **Packaging (already committed, needs a build).** pkgrel 17 stops
   `dtbs_install` shipping 1841 DTBs into a 226 MiB `/boot`. Until an r17 image
   exists, kernel apk upgrades on the device fail mid-transaction **and exit
   0**. Hash modules; never trust the exit code.
5. **Camera.** Next step is the probe milestone: enable `&camss` on joan and
   look for the CSIPHY HW version read. Do this as a deliberate boot test, not
   folded into a headset-test image — it powers up GDSCs that have never run.
6. Everything else from the 2026-09-12 twelve-item list stands.

## Repo state

- kernel `joan/jack-irq-level-v2` @ `ff98974a67aa` — pushed. Both wcd934x
  patches + the specifier fix, all verified on hardware. Candidate for
  cherry-picking to `master` (which is verified-fixes-only).
- kernel `joan/camss-msm8998-dt` @ `110f579bd5ac` — local only, not pushed.
- pmaports fork `joan/readme-build-guide` @ `be4340aa62` — pushed to `ghjoan`.
- lg-v30-port `ember/pmaports-joan-gpu-publish-handoff` — pushed to `ghpub`.

**Remote names are not `origin`.** lg-v30-port uses `ghpub`; the pmaports fork
uses `ghjoan` and its `origin` is *upstream postmarketOS*. `git push origin`
from the pmaports tree aims at upstream. Check `git remote -v` first.

## Build environment changed this session

pmbootstrap's workdir is now `/data/buildcache/pmbootstrap-joan` — a btrfs
subvolume on the **HDD** (`/dev/mapper/data`), `compression none`, CoW and
checksums kept. ccache is 50 G with `hash_dir = false`; a full joan build is
~1.6 GB of entries, so it holds ~30 builds (the old 5 G cap held about 2 and
thrashed). Convention note posted to Honcho as
`mesh-note-hdd-buildcache-btrfs-20260912`.
