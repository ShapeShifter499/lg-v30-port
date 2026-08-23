# joan — cellular bring-up: LTE registration working (2026-08-22)

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-08-22

## Headline

**The LG V30 registers on LTE under mainline + pmOS.** T-Mobile, 310/260,
-57 dBm, CS and PS both attached, and a data bearer establishes with a real
routable IPv6 address.

Not yet working: data packets do not actually flow through QMAP/IPA, and voice
needs VoLTE, which is not up.

## The blocker was one missing firmware file

The modem booted and then died:

```
qcom-q6v5-mss 4080000.remoteproc: fatal error received:
    ipa_util.c:1094:IPA Assert: ipa_util.imm_cmd.clients[cmd_handle].init_done ==
remoteproc remoteproc0: crash detected in 4080000.remoteproc: type fatal error
```

The modem asserts inside its own IPA client init.  The cause is on the
**apps** side:

```
ipa 1e40000.ipa: Direct firmware load for ipa_fws.mdt failed with error -2
ipa 1e40000.ipa: probe with driver ipa failed with error -2
```

`ipa_fws.mdt` was missing, so the AP's IPA driver never probed, so the modem's
handshake with it asserted.  The firmware is on the device itself, in the same
place the modem firmware came from:

```sh
mount -o ro /dev/disk/by-partlabel/modem /mnt/modemfw
cp /mnt/modemfw/image/ipa_fws.* /lib/firmware/
```

(It is also at `/system/etc/firmware/ipa_fws.*` on the Android system
partition.)

**It must be in the initramfs, not just on the rootfs.**  IPA probes at
~1.4 s, long before the SD-card rootfs is mounted, so a copy in
`/lib/firmware` on the rootfs is found too late and the probe still fails.
Adding it to the initramfs (`lib/firmware/` in the ramdisk, alongside the
crnv21.bin already there) gives:

```
[1.375147] ipa 1e40000.ipa: IPA driver initialized
[1.718836] ipa 1e40000.ipa: IPA driver setup completed successfully
```

and **zero IPA asserts** thereafter.  Rebinding the driver by hand after boot
also works for registration, but leaves `unexpected init_completed response`
and an incomplete handshake — do it properly via the initramfs.

## Kernel config change required

`CONFIG_RMNET=m` -> **`CONFIG_RMNET=y`**.  This kernel has no modules installed
on the rootfs, so anything built `=m` simply does not exist.  With RMNET built
in, `rmnet_ipa0` appears and ModemManager can create `qmapmux0.0`.

(`CONFIG_WWAN` stays `=m`; it is only selected by module-only MHI options and
is not needed — QMI is spoken over QRTR sockets directly.)

## Bring-up sequence that works

Order matters: IPA must be up before the modem starts.

```sh
# 1. IPA firmware must already be in the initramfs (see above)
# 2. modem
echo start > /sys/class/remoteproc/remoteproc0/state
# 3. support daemons
LD_LIBRARY_PATH=/tmp/bin /tmp/bin/tqftpserv &     # from nest joanfw.tgz
rmtfs -r -P -s &
# 4. radio on - it comes up in 'shutting-down' otherwise
qmicli -d qrtr://0 --dms-set-operating-mode=online
# 5. ModemManager
ModemManager &
mmcli -m 0 --simple-connect="apn=fast.t-mobile.com,ip-type=ipv4v6"
```

Give the modem ~25 s after start: the core telephony QMI services (WDS 1,
NAS 3, WMS 5, UIM 11) register noticeably later than the first batch.  An
early `qrtr-lookup` showing only services like 15/21/22/23 is not a failure,
just impatience.  **`pd-mapper` was not needed.**

## Verified state

| | |
|---|---|
| SIM | `Card state: present`, `Application state: ready`, PIN1 disabled |
| IMEI | read via `--dms-get-ids` |
| Registration | `registered`, CS `attached`, PS `attached`, `3gpp`, `lte` |
| Operator | T-Mobile, MCC 310 MNC 260 |
| Signal | -57 dBm (91%) |
| ModemManager | finds the modem, `Voice | emergency only: no` |
| Data bearer | connects, APN fast.t-mobile.com, real IPv6 /64 + gateway |

Tools installed on the phone (Alpine community): `libgpiod`, `qrtr`,
`qrtr-libs`, `qmi-utils`.

## Open: data packets do not flow

The bearer connects and hands out a valid address, but nothing traverses it:
`qmapmux0.0` counts tx packets and **zero** rx, and the bearer's own byte
counters stay frozen at their post-connect values.  No kernel errors, no IPA
debugfs, and `--wda-get-data-format` returns `InvalidArgument`.

IPv6 note: the address comes up `tentative` because DAD does not complete on
this link.  Disable it *before* adding the address —
`echo 0 > /proc/sys/net/ipv6/conf/qmapmux0.0/accept_dad` — busybox `ip` has no
`nodad`.  That gets the address to `global` but does not by itself fix the
data path.

### Root cause found: IPA runtime PM deadlocks

```
/sys/devices/platform/soc@0/1e40000.ipa/power/runtime_status  ->  suspending
```

The device sticks in `RPM_SUSPENDING` forever: `ipa_runtime_suspend()` enters
`ipa_endpoint_suspend()`/`gsi_suspend()` and never returns.  Every
`pm_runtime_get()` from `ipa_start_xmit()` then fails and each uplink packet is
dropped.  Writing `on` to `power/control` **also blocks**, because the pending
suspend never completes.

Worked around in `2631e1503`: take a permanent runtime PM reference once setup
completes, so the device never idles into that path.  With it, `runtime_status`
reads `active` and the kernel boots clean.

Two traps found the hard way:

- Do **not** call `pm_runtime_forbid()` from `ipa_power_init()`.  It resumes the
  device before the driver data is installed, so `ipa_runtime_resume()`
  dereferences garbage and the kernel hangs during probe.  Take the reference
  after `ipa->setup_complete = true` instead.
- Read the **child's** counters as well as the parent's.  rmnet's own drops land
  on the rmnet child (`qmapmux0.0`), not on `rmnet_ipa0`; watching only the
  parent hides where packets go.

### Still open after that fix

Data *still* does not flow.  Measured over 40 large pings with IPA `active`:

```
qmapmux0.0   tx 12 -> 53   (42 KB)   tx_dropped 0
rmnet_ipa0   tx  3 ->  3   unchanged  tx_dropped 7 unchanged
```

rmnet accepts and forwards, and IPA neither transmits nor drops - consistent
with the netdev TX queue being stopped and never woken (`ipa_start_xmit()`
calls `netif_stop_queue()` unconditionally on entry and only re-wakes it when
power is ACTIVE).

Trying to reset that queue revealed the deeper problem: **`ip link set
rmnet_ipa0 down` hangs too.**  Worse, it hangs *holding the RTNL lock*, so every
later netlink call blocks behind it and the box needs a reboot.  Do not run it.

### Narrowed further: GSI transfers never complete

Ruled out, each on hardware:

- Not the parent being down: `rmnet_ipa0` is `<UP,LOWER_UP>` and `ipa_open()`
  (which calls `netif_start_queue()`) has run.
- Not uplink aggregation: forcing `egress_agg_params.count` to 1 in
  `rmnet_map_update_ul_agg_config()` changed nothing.  (The driver default is
  already 1; userspace raises it.)  Patch reverted.
- Not rmnet dropping: the child (`qmapmux0.0`) counts every packet as
  transmitted with `tx_dropped 0`, so rmnet reaches `dev_queue_xmit()`.

What is left, and what the counters say:

```
qmapmux0.0   tx 19    tx_dropped 0     rmnet hands them to the parent
rmnet_ipa0   tx  3    tx_dropped 7     frozen from early boot
GSI irq                          15    frozen
bearer bytes tx                  48    frozen
```

Three packets went out early and **their completions never came back** - the
GSI interrupt count does not move.  With no completions the TX ring never
drains, `ipa_endpoint_skb_tx()` then fails, and `ipa_start_xmit()` returns
`NETDEV_TX_BUSY`, which requeues without touching any netdev counter.  That is
exactly the observed signature, and it also explains why both
`ipa_runtime_suspend()` and `ipa_stop()` hang: each waits on endpoint/GSI
state that never settles.

So the real defect is that **GSI transfers do not complete on IPA v3.1**.  The
runtime-PM workaround in `2631e1503` is still worth having (it removes the
RPM_SUSPENDING deadlock and lets the box boot and stay usable), but it does not
address this.

### Corrected again: it is rmnet uplink aggregation, not GSI

`ipa_start_xmit()` was instrumented (`b485d525a`) so that both silent failure
paths log.  With that kernel, **no message ever appears** - so the function is
never called at all.  That rules out the stalled-ring/GSI theory above: the
packets never reach IPA.

Working back, the only path in `rmnet_egress_handler()` that increments the
child's counters, records no drop, and never calls `dev_queue_xmit()` on the
parent is the `-EINPROGRESS` return from `rmnet_map_tx_aggregate()`.  So the
packets sit in rmnet's uplink aggregation buffer and are never flushed.

Confirmed shape of the failure:

```
qmapmux0.0   tx 12   tx_dropped 0    accepted, "transmitted"
rmnet_ipa0   tx  3   tx_dropped 7    frozen; ipa_start_xmit never runs
GSI irq                        15    frozen (consistent - nothing is submitted)
```

Two attempts to disable it, and how they went:

- **Kernel side**: clamping `count` to 1 in `rmnet_map_update_ul_agg_config()`
  built and booted, but the modem bring-up crashed the kernel twice out of two
  attempts, where the same kernel without the clamp was reliable.  Reverted
  rather than debugged.
- **Modem side**: setting `ul-protocol=disabled` via
  `--wda-set-data-format` before connecting does not survive - ModemManager
  re-negotiates the data format when it brings the bearer up and turns
  aggregation back on.

So the fix has to prevent ModemManager from enabling uplink aggregation, or
make the flush actually fire.  Worth checking why the hrtimer armed in
`rmnet_map_tx_aggregate()`'s `schedule:` path never expires here, and what
`egress_agg_params.count`/`.bytes`/`.time_nsec` MM actually installs (iproute2
does not print them; they arrive over netlink as `IFLA_RMNET_UL_AGG_PARAMS`).

### Final state of the investigation, and a warning about the instruments

The aggregation conclusion above is **also wrong**.  Creating a fresh rmnet link
by hand (`ip link add link rmnet_ipa0 name rmnet0 type rmnet mux_id 1`, which
re-runs `rmnet_map_tx_aggregate_init()` with the driver default of count 1, so
aggregation is definitively off) changes nothing: the child still counts
transmits and the parent still shows none.

With a bounded, non-rate-limited log at the top of `ipa_start_xmit()`, the
picture during one 5-ping attempt is:

```
JOAN-IPA: ENTRY len=84  proto=0xf9      <- ETH_P_MAP, correctly framed
JOAN-IPA: ENTRY len=56  proto=0xf9
JOAN-IPA: ENTRY len=104 proto=0xf9
child qmapmux0.0 tx 11 / drop 0
parent rmnet_ipa0 tx 3 / drop 7         <- unchanged before and after
```

Exactly three packets enter the driver, all correctly framed, and they leave no
trace at all: no `tx_packets`, no `tx_dropped`, and no failure log despite 37
unused log slots.  Every path out of that function should touch one of the
three.  That is unexplained and is where the next session should start.

**A warning worth more than any of the theories above:** this investigation
reached three different confident conclusions (GSI completion, uplink
aggregation, the queue layer) and each was an artefact of the instrument, not
evidence:

- Logging only the *failure* paths made "never called" indistinguishable from
  "called and succeeded".
- `net_ratelimited_function()` silently drops after ~10 messages per 5 s, so an
  absent message means nothing.
- The rmnet child and the IPA parent keep separate counters; reading only one
  hides where packets go.

Log unconditionally with a bounded budget, and check both netdevs, before
believing any conclusion here.

### The actual root cause, consistent with every observation

`ipa_endpoint_disable_one()` / GSI channel stop **hangs on this hardware**.
Everything else follows from that:

1. `ip link set rmnet_ipa0 down` wedges, three times out of three, in an
   uninterruptible wait - `timeout` cannot kill it, and it holds the RTNL lock,
   so all later netlink calls block and the device needs a reboot.
   `ipa_stop()` calls `ipa_endpoint_disable_one()`, so that is the hang.
2. `ipa_runtime_suspend()` calls `ipa_endpoint_suspend()` on the same path,
   which is why the device sticks in `RPM_SUSPENDING` forever and why writing
   `on` to `power/control` also blocks.
3. The workaround in `2631e1503` (hold a permanent runtime PM reference)
   removes the suspend deadlock and lets the box boot and stay usable - but it
   **breaks the transmit queue**, because:

```
ipa_modem_wake_queue_work()   /* the ONLY external netif_wake_queue() */
    is scheduled from ipa_modem_resume(), i.e. the runtime PM *resume* path
```

   With a permanent reference the device never suspends, so it never resumes,
   so that wake never runs.  `ipa_start_xmit()` calls `netif_stop_queue()`
   unconditionally on entry and, on the `NETDEV_TX_BUSY` return, leaves it
   stopped expecting a resume to re-enable it.  Once that happens early in boot
   (the 3 tx / 7 drops seen on every boot), the queue is stopped forever: a
   stopped queue means `ipa_start_xmit()` is never called again, so it cannot
   wake itself, and the only external waker is disabled.

That is the deadlock, and it explains the whole signature: rmnet forwards,
`dev_queue_xmit()` is called, the driver is never entered, and no counter
anywhere moves.

**So the fix is not another workaround at the queue or aggregation level - it is
to make GSI channel stop work.**  Until then any PM workaround trades a boot
hang for a dead transmit queue.  Start from `gsi_channel_stop()` /
`ipa_endpoint_disable_one()` and diff the channel state machine against
downstream `drivers/platform/msm/ipa/ipa_v3`, which drives the same hardware.

Useful facts for that work:

- The IPA<->modem QMI handshake *does* complete: dmesg shows `received modem
  starting event` then `received modem running event`.
- IPA is hard-configured for QMAP: `feature/rx_offload = MAPv4`,
  `tx_offload = MAPv4`, modem endpoints rx 16 / tx 3.
- `ipa_start_xmit()` requires `skb->protocol == ETH_P_MAP`, so the rmnet mux
  child is **mandatory** - it is not double-wrapping, as it first appears.
- busybox `ip` cannot show rmnet details.  Extract `sbin/ip` from Alpine's
  `iproute2-minimal` apk plus `libmnl.so.0` and run it with
  `LD_LIBRARY_PATH`; a full `apk add` fails because optional libcap
  subpackages cannot be fetched without internet on the phone.

## Open: voice needs VoLTE

A call attempt is refused by the modem:

```
QMI protocol error (90): 'IncompatibleState'   -> call state: terminated
```

That is the modem declining a circuit-switched call.  **T-Mobile US has retired
2G/3G**, so there is no CS fallback: voice on this SIM requires VoLTE, i.e. IMS.

The good news is the modem does expose IMS: `qrtr-lookup` lists proprietary
services **700-707 and 800** (IMS presence / video telephony / application /
settings), so the IMS stack is present in the firmware.  Bringing VoLTE up
means establishing the IMS PDN and driving IMS registration over those
services — libqmi does not implement them, so this is reverse-engineering
work, which Lance has approved.

Note also that call audio is a separate problem: joan's earpiece does not
work (see `2026-08-22-tfa9872-fix-and-slimbus-playback.md`), so even a
connected call would need loudspeaker or headphones.

## mmcli gotcha

Calls are selected with `-o` / `--call=`, not `-c`.  Passing a call object
path to `-c` prints "no call was specified" and then **segfaults**.
