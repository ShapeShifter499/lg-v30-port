# Boot 21b — netconsole revived, and it ends on the same line

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-21
Kernel: identical to 21a (7.2.0-rc2-g0d00bab2b7ce-dirty, build #38)
Image: boot-joan-qmidbg21b.img
(sha256 46665c21a40065075a69c41add936a2560f2ecf7668407d23625cb46da91e836)
Capture: /tmp/joanrun/boot21b/netconsole.txt on nym-nest — 12677 lines, 1.24 MB
Same knobs as 21a: `autosuspend_ms=600000 joan_pipes=0`

## The rig finding: netconsole has never worked in this campaign

Not the MAC — the target never initialised at all:

```
[3.053319] netconsole: netconsole: local port 6665
[3.053891] netconsole: netconsole: interface name 'usb0'
[3.054911] netpoll: netconsole: usb0 doesn't exist, aborting
[3.055109] netconsole: Not enabling netconsole for cmdline0. Netpoll setup failed
```

The `netconsole=` cmdline target is brought up by an initcall at ~3 s; the
USB gadget that provides `usb0` appears far later. So every boot carrying
that cmdline transmitted nothing, and its silence carried no information.

A second, independent defect sat behind it: the cmdline pins the remote MAC
to `92:e9:43:17:eb:60`, and pmOS randomises the CDC host MAC every boot —
nest's was `9a:0d:a2:dd:68:63`, then `ce:65:22:5e:3d:7e`, then
`ee:ee:58:f4:b7:6f` across three boots this session.

**Fix (no rebuild needed):** configure netconsole through configfs after
`usb0` is up, with nest's MAC read live at setup time:

```sh
mount -t configfs none /sys/kernel/config     # if not mounted
mkdir /sys/kernel/config/netconsole/joan
cd    /sys/kernel/config/netconsole/joan
echo usb0 > dev_name;  echo 172.16.42.1 > local_ip;  echo 6665 > local_port
echo 172.16.42.2 > remote_ip;  echo 6666 > remote_port
echo "$(cat /sys/class/net/enp0s29u1u5/address)" > remote_mac
echo 1 > enabled
```

Listener on nest: `nc -u -l -p 6666 >> capture.txt` (no socat on nest).

`boot-test-21b.sh` does this and then **positive-controls** the channel: a
unique marker is pushed through `/dev/kmsg` and must appear in the capture
within 15 s, otherwise the run aborts before spending the audio sequence.
That gate fired on the first attempt and is the only reason this was caught
rather than being read as another silent death. See
[[feedback-validate-debug-channels]].

## Result: both channels end on the same line

netconsole is synchronous — each printk is transmitted at the point of the
call, with no buffer to lose. It ends at:

```
[58.577597] ... 'apr_audio_svc' data rx (liid 7 len 40)
[58.577866] ... 'apr_audio_svc' rx_done sent (liid 7 reuse 1)
```

which is the *same last line* as 21a's 50 ms SD logger (there at
[108.203955]). Exactly 33 lines follow the 58.0 s mark in each. So the
kernel emits **nothing** after acking the seventh APR response — no fault,
no warning, no panic, no reschedule.

## Runtime PM, conclusively

Four `JOAN-PM` breadcrumbs in the entire 12677-line boot:

```
[34.582982] JOAN-PM: runtime_resume enter (state 3)          <- DOWN -> AWAKE
[34.591397] JOAN-PM: init_dma enter (rx=0000000000000000 tx=0000000000000000)
[34.594952] JOAN-PM: init_dma done ret=0
[34.595863] JOAN-PM: runtime_resume done ret=0 state=0 prev=3
```

No `runtime_suspend`, no `exit_dma`, from 34.58 s through the death at
58.58 s. The bus was pinned awake across the whole stream setup and the
phone died anyway.

## The death window, in full

```
[58.543640] JOAN-DBG: posting mc=0x60 mt=0x0 la=0xce   (codec IFD reads)
[58.544954] JOAN-DBG: posting mc=0x68 mt=0x0 la=0xce   (codec IFD writes)
[58.545283] JOAN-DBG: q6slim_hw_params dai id 2 rate 48000 fmt 2
[58.545698] JOAN-DBG: q6afe_dai_prepare dai id 2 started 0
[58.545796] JOAN-DBG: slim port 16384 cfg: dev 1 rate 48000 width 16
                      ch 1 fmt 0 map 144/0/0/0
[58.546..58.578] apr_audio_svc: seven responses, liid 1..7, len 40/40/36/40/40/40/40
                 each one rx_done sent; liid 1..6 also see the ADSP's own
                 rx_done come back; liid 7's never does.
<nothing, ever again>
```

32 ms from the port config to silence.

## Other things this capture shows

- `[36.836528] qcom,slim-ngd-ctrl: QMI wait timeout` — the SLIMbus QMI
  service (769) still never registers, as of the 08-16 finding. The
  controller registers anyway at 35.82 via the other path, so this is a
  redundant `up_worker` timing out, not a new fault. But it does mean
  `ctrl->qmi.handle` handling is worth re-checking.
- `qcom-soundwire wcd934x-soundwire.2.auto: din-ports (2) mismatch with
  controller (6)`.
- A long list of `ASoC: mux ... has no paths` on the codec (RX INT0-7 MIX2
  INP, CDC_IF TX9/10/11/13) — DAPM incompleteness, consistent with the
  "no audio-routing in joan DT" note.
- The `Tainted: [W]=WARN` stack dumps at 34.65/34.68 are Aurel's own
  `dump_stack()` breadcrumb in `qcom_slim_ngd_get_laddr` (f173f0394), not a
  new warning.
- **Capture artifact:** the first three lines of netconsole.txt carry
  timestamps 140-148 s. They are the *previous* pmOS session flushing as it
  rebooted, caught because the listener starts before the boot. The run's
  own log begins after them, from ~0 s.

## Next instrumentation (one rebuild, one boot)

The open fork is whether the apps CPU outlives the ADSP. Two additions
answer it and name the failing command:

1. **APR header logging** on the rx path: opcode, src/dst service, token.
   "len 40" is not enough — we need to know *which* AFE command's response
   is the seventh, and therefore what the ADSP was doing when it stopped.
2. **A heartbeat timer** (20 ms, param-gated) over netconsole. If dozens of
   heartbeats follow the last APR line, the apps CPU is fine and the ADSP
   took the SoC down; if none do, the apps CPU wedged at that instant and
   there is an MMIO access to find.
