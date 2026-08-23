# joan cellular data — the GSI diagnosis was wrong, and what the hardware says

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-08-23

Supersedes the **CELLULAR / Data** section of `HANDOFF-2026-08-22-next-session.md`.
Everything that handoff says about audio, Wi-Fi, Bluetooth and the bring-up
recipe still stands.

## DATA WORKS

```
20 packets transmitted, 20 packets received, 0% packet loss   (2606:4700:4700::1111)
round-trip min/avg/max = 30.545/61.077/190.722 ms
 5 packets transmitted,  5 packets received, 0% packet loss   (2001:4860:4860::8888)
rmnet_ipa0 tx=40 rx=68 | qmapmux0.0 tx=40 rx=36
modem state: connected, lte, T-Mobile, packet service attached
modem crashes since boot: 0
```

Two changes were needed, both derived from the stock driver:

1. **`wrr_weight = 1`** in `gsi_channel_program()` — mainline programs a GSI
   round-robin weight of **zero** on every non-command channel, where
   downstream programs 1 and `msm_gsi.h` says "must be >= 1".  A zero weight
   starves the channel; this is why only the command channel ever worked.

2. **`ipa.lowmem=1`** — a 1 MB scratch page mapped at IOVA 0 in the IPA's
   IOMMU domain.  Something in the IPA DMAs to a near-null address the moment
   the uplink channel really runs; unmapped, that raises an SMMU translation
   fault at `iova=0x38` which cascades into a GSI bus error, an IPA
   microcontroller error, and finally the modem asserting inside its own IPA
   HAL and crashing.  Giving that address real memory makes the access
   harmless and the whole path comes up.

The second is a **workaround, not a fix** — the right answer is to find what
performs that access and give it a proper mapping.

### What the scratch page revealed about that access

Keeping the scratch mapping around and reading it back afterwards
(`.../1e40000.ipa/lowmem`) answers two questions the fault alone could not:

* **Nothing is ever written into it.**  After sustained traffic the region is
  byte-for-byte as allocated.  Combined with `FSYNR0 = 0x2` — the WNR bit
  (bit 4) is clear, and the arm-smmu driver prints no `WNR` flag — the
  faulting access is a **read**, not a write.  IPA dereferences a near-null
  pointer and reads.

* **The value read matters.**  Filling the region with `0xa5` instead of zeroes
  (`ipa.lowmem_poison=1`) produces no SMMU fault and no modem crash, but data
  stops flowing.  So IPA *consumes* what it reads: zeroes happen to be benign,
  garbage silently breaks the data path without reporting anything.

That rules out the convenient fix ("stop the null dereference and any mapping
will do") and means a real fix has to supply the right content — which first
requires identifying the structure IPA believes it is reading.  An offset of
`0x38` is 56 bytes, i.e. entry 3 of a 16-byte-element ring, or entry 7 of an
8-byte table.

Both results are **confirmed across two independent boots** each, against
several zero-fill boots where data works (20/20, 5/5 and 8/8 ping runs).  The
poison run reproduces exactly: `8 packets transmitted, 0 received`, scratch
unmodified before and after, no SMMU fault and no modem crash.

Rig note: a full boot-and-bring-up cycle takes longer than an ssh command
timeout allows, and killing the ssh loses the result.  Launch it detached on
nest instead and poll the log:

```sh
ssh nest 'setsid bash -c "bash /tmp/nest-cycle.sh > /tmp/cyc.log 2>&1" \
          < /dev/null > /dev/null 2>&1 &'
```

### Suggested next experiment

Since the *content* matters, bisect it: zero the whole scratch except a small
window, poison only that window, and see which window breaks the data path.
Starting with bytes `0x38`-`0x3f` would confirm whether the faulting offset is
also the meaningful one, or merely the first byte of a larger structure that
IPA walks.

### A landmine in the experimental def_rt_ep path

`ipa_table_reset_add()` calls `ipa_table_addr(ipa, false, count)` for **both**
filter and route table resets - passing `false` deliberately, to get the entry
array without the filter bitmap.  The `ipa.def_rt_ep` probe added here changes
what that `false` returns, so with the probe enabled a filter table reset would
be filled with *route* rule addresses.  Harmless at the default of -1, but the
probe must not be enabled without fixing this first.  But it confirms the
diagnosis exactly, and it is what makes the data path usable today.

With both in place: GSI interrupts flow (`isr total 29 ieob 29`), every
transaction completes (`id f15 a15 c15 p15 k15 l15`), the ring drains
(`ch_rp == ch_wp`), and traffic passes in both directions.

## One-line state

**Cellular data works.**  Two changes were needed: a one-line GSI scheduling
fix (round-robin weight of zero starved every non-command channel) and a
scratch mapping that absorbs a near-null IPA DMA which was otherwise faulting
the SMMU and crashing the modem.

Modem bring-up is reproducible (T-Mobile LTE, CS+PS attached, bearer connects
with a real IPv6 /64).  **Data still does not flow — in either direction.**  The
previous "event ring full / doorbell never rung" diagnosis **does not
reproduce** and is wrong.  The real observation is much narrower: the IPA
consumes roughly one transfer per direction and then stops, and everything
else that was previously reported is downstream fallout from that.

## Correction to the 2026-08-22 handoff

That document named `gsi_evt_ring_update()`'s early `return` as prime suspect,
on the theory that the event ring filled and was never handed back.  Measured
directly, on every boot this session:

| claim | measurement |
|---|---|
| event ring full | ch5 event ring holds **1 of 512** entries |
| doorbell never rung | `eru doorbell` counts match `eru enter`; no early return ever taken (`eru null 0`) |
| `GSI_OUT_OF_BUFFERS` | `ERROR_LOG` reads `00000000` on every boot |
| GSI interrupts frozen at 15 | those 15 are channel/event **command completions** at init, not IEOB |

The `GSI command 2 ... timed out` / `OUT_OF_BUFFERS` / oops sequence in that
handoff was almost certainly recorded **after a modem crash**, while tearing
down a pipe whose peer was already dead.  It is a symptom of the crash, not the
cause of the data failure.

Do not re-open `gsi_evt_ring_update()`.

## What the hardware actually says

Read back from registers while the failure is live (channel 5 =
`IPA_ENDPOINT_AP_MODEM_TX`, endpoint 3):

```
ch5  TX state 2 tre 3/512 avail 495 id f3 a3 c3 p1 k1 l1
     ch_rp ffff6010 ch_wp ffff6030
```

TREs are 16 bytes and the ring base is `0xffff6000`, so:

* `ch_wp` = index **3** — the AP told hardware about all three TREs.
* `ch_rp` = index **1** — hardware consumed **one** and stopped.

The command channel on the same GSI, same boot, drains completely
(`ch_rp == ch_wp`).  So GSI itself is healthy; the doorbell is correct; the
transaction bookkeeping is correct.  **IPA accepted one uplink packet and then
stopped fetching.**

Downlink is in the same state: 249 RX buffers posted on channel 8,
`ch_rp` at index **0**, `rx_packets` **0** on both `rmnet_ipa0` and
`qmapmux0.0`.  The bearer's own `bytes rx/tx` counters are modem-side and do
not contradict this.

**Both directions are dead at the IPA↔modem boundary, at roughly one transfer
each.**  That reframes the problem: this is not a transmit bug.

## Why "packets never reach the driver" was seen

That earlier observation was real but is a second-order effect, and the chain is
now fully traced:

1. IPA stops completing transfers on channel 5.
2. `ipa_gsi.c` feeds byte-queue-limits — `netdev_sent_queue()` on commit
   (line 38), `netdev_completed_queue()` on completion (line 49).  With no
   completions, BQL's in-flight count never drains.
3. BQL latches `__QUEUE_STATE_STACK_XOFF` on the netdev's TX queue.
4. `pfifo_fast` stops being dequeued; the backlog grows.
5. `ipa_start_xmit()` is therefore never called again.

Measured: `qdisc pfifo_fast qlen 10`, `txq_state 2`, and an `ipa_start_xmit()`
entry counter that stays at **0** while `qmapmux0.0` accepts six more pings.

Note BQL's limit starts at zero, so uplink is gated to one packet at a time
until the first completion arrives.  A driver that never completes gets exactly
the behaviour seen here.

## Ruled out — by hardware readback, not by reasoning

Each of these was a live suspect and each is now closed.  Do not re-check.

| suspect | evidence |
|---|---|
| rmnet TX aggregation holding packets | `ul agg config bytes 4096 count 1` — the `count > 1` branch is never taken.  Stock refuses UL aggregation on msm8998 outright (`"WAN UL Aggregation not supported!!"`) |
| `skb->protocol != ETH_P_MAP` drops | per-reason xmit counters all zero |
| endpoint DELAY / SUSPEND flow control | `ep3 ctrl 00000000` |
| per-packet uplink STATUS | set `.status_enable = false` to match stock; register went to `status 00000000`, behaviour **identical**.  Reverted. |
| uplink checksum framing mismatch | rmnet `data_format 0000000d` includes `EGRESS_MAP_CKSUMV4`; IPA has `cfg 0000000a` (`CS_OFFLOAD_UL`, metadata offset 1) and an 8-byte header — they agree, and agree with stock |
| IPA source resource-group limits | mainline `ipa_resource_src[]` matches the stock `ipa3_rsrc_src_grp_config` table exactly |
| endpoint sequencer type | `seq 00000004` = stock's `IPA_DPS_HPS_SEQ_TYPE_2ND_PKT_PROCESS_PASS_NO_DEC_UCP` |
| IPA local memory map | mainline `ipa_mem_local_data[]` matches stock's `qcom,ipa-ram-mmap` in `msm8998.dtsi` byte for byte, through `MODEM 0xbd8/0x1424` and `END 0x2000` |
| BEI blocking the TX completion interrupt | the command channel runs with BEI set and *does* raise IEOB (`MODC = 1`), so BEI is not suppressing interrupts on this hardware |

## A separate, real finding: IPA runtime PM crashes the modem

With `power/control = auto` (the default), the first uplink packet triggers a
runtime resume and then:

```
ipa 1e40000.ipa: JOAN-IPA: tx busy, pm_runtime_get=0
qcom-q6v5-mss 4080000.remoteproc: fatal error received:
    ipa_hal.c:2292:IPA Assert: !((ipa_hal.irq.irq_stts.value & ipa_cfg.hw.irq_enab
ipa 1e40000.ipa: received modem crashed event
```

That is the **modem's own IPA HAL** asserting that its IRQ status contains a bit
its configuration did not enable.  With

```sh
echo on > /sys/bus/platform/devices/1e40000.ipa/power/control
```

set before the modem is started, the crash does not occur across repeated runs.
Pin it during any data debugging — otherwise you are chasing a corpse.  The
string is truncated at source by the SMEM error buffer; the modem's `ipa_hal.c`
is AMSS firmware and is not in any available tree.

Note this is *not* the "permanent runtime PM reference" approach the 2026-08-22
handoff rejected.  That was a code change that broke transmit because
`ipa_modem_wake_queue_work()` is scheduled from the resume path.  Pinning via
sysfs before any traffic means `pm_runtime_get()` returns 1 immediately and the
wake is never needed.

## The decisive experiment: IPA is not fetching

BQL starves the ring, so "no completions" and "hardware not fetching" look
identical.  Bypassing BQL at runtime (`ipa.bql` module parameter plus a
`bqlreset` command that clears the latched XOFF) separates them:

```
xmit calls 46 ok 44          <- ipa_start_xmit() now runs; BQL really was the gate
tx   commit 44 bei 44
ch5  TX tre 47/512
     ch_rp ffff6010 ch_wp ffff62f0 db 37 last_db ffff62f0
     ev2  sw 1/512 hw_rp ffff8010=1
isr  total 0
```

`ch_wp` is index **47** and the doorbell was rung 37 times, yet `ch_rp` is
still index **1** and exactly one event has ever been posted.  **Hardware was
told about 47 transfers and consumed one.**

So the completion path is not the problem — GSI/IPA genuinely stops fetching
after the first transfer.  That closes the entire "events are being lost"
branch, including anything to do with BEI or interrupt moderation.

Note `xmit drop proto 2 last_proto 86dd`: a couple of raw IPv6 packets are sent
on `rmnet_ipa0` directly rather than through the mux child and are dropped for
not being `ETH_P_MAP`.  That is normal and accounts for the stale `tx_dropped`
counts seen earlier; it is not the data path.

**Do not boot with `ipa.bql=0`.**  With no backpressure and a ring that never
drains, `ipa_endpoint_skb_tx()` eventually returns `-EBUSY`, `ipa_start_xmit()`
returns `NETDEV_TX_BUSY` with the queue awake, and the qdisc spins in the
transmit softirq until the phone wedges.  Toggle it at runtime after bring-up
and keep the test well under the 511 available TREs.

## Also ruled out, with register readback

* **The AP↔modem QMI handshake completes in full.**  Every milestone fires:
  `qmi work 1 rsp 1 ind_reg 1 drv_cmplt 1 bye 0 send_ret 0`, and
  `setup_complete 1 uc_loaded 1 modem_state 2`.  Since `ipa_qmi.h` states the
  modem will not touch IPA hardware until this completes, and the modem has
  demonstrably programmed its own endpoints (ep5 carries `cfg 00000005`, which
  only the modem writes), the modem side is up.
* **Every endpoint register matches intent.**  `ENDP_INIT_HDR/_EXT/_AGGR/
  _DEAGGR/_HOL_BLOCK` were dumped for all seven defined endpoints.  ep3 reads
  `hdr 00000048` — `HDR_LEN` 8 with `HDR_OFST_METADATA_VALID` set at offset 0,
  which upstream does deliberately (`/* For QMAP TX, metadata offset is 0
  (modem assumes this) */`).  ep16's metadata offset 1 and packet-size offset 2
  match the QMAP header layout.  No HOL blocking anywhere.
* **Resource group limits are programmed correctly**, verified by reading the
  `SRC_/DST_RSRC_GRP_*` registers back rather than trusting the writes.

### An upstream divergence found on the way (not the bug)

Mainline's `IPA_RESOURCE_TYPE_SRC_ACK_ENTRIES` table for IPA v3.1 carries the
descriptor *buffer* counts rather than the descriptor *list* counts:

| type | downstream UL/DL | mainline UL/DL | Σ minimums |
|---|---|---|---|
| `SRC_DESCRIPTOR_LISTS` | 14 / 16 | 14 / 16 | 48 |
| `SRC_DESCRIPTOR_BUFF` | 19 / 26 | 19 / 26 | 63 |
| `SRC_ACK_ENTRIES` | 14 / 16 | **19 / 26** | 48 → **63** |

Every other deliberate deviation in that file is commented ("3 downstream",
"7 downstream"); this one is not, which suggests a copy-paste from the block
above it.  Setting it back to 14/16 was tested: the registers changed
(`src7 14/14 16/16`, confirmed by readback) and the behaviour did **not**
change, so it is not the cause here — but it is still worth sending upstream.
The change has been reverted from the working tree.

## Root cause located: mainline drops two QMI requests from the modem

The `JOAN-DBG: qmi unmatched` logging added in an earlier session (in
`qmi_invoke_handler()`) shows the modem sending the AP two IPA QMI **requests**
during bring-up that mainline has no handler for:

```
[55.693155] JOAN-DBG: qmi unmatched from node 0 port 30 type 0 id 0x27 len 20
[55.993561] JOAN-DBG: qmi unmatched from node 0 port 30 type 0 id 0x23 len 20
```

Against `include/uapi/linux/ipa_qmi_service_v01.h` in the stock tree:

| id | message | what stock does with it |
|---|---|---|
| `0x23` | `QMI_IPA_INSTALL_FILTER_RULE_REQ_V01` | the modem hands the AP its **uplink filter rules**; the AP caches them (`num_q6_rules`) and installs them per QMAP mux channel via `ipa3_wwan_register_to_ipa()`, setting `ul_flt_reg` |
| `0x27` | `QMI_IPA_CONFIG_REQ_V01` | the modem hands the AP its IPA configuration |

Both are `QMI_REQUEST` (type 0), so the modem **blocks waiting for a response
that mainline never sends**.  Mainline's `ipa_server_msg_handlers[]` covers only
`INDICATION_REGISTER` (0x20), `INIT_DRIVER` (0x21), `INIT_COMPLETE` (0x22) and
`DRIVER_INIT_COMPLETE` (0x35).

This fits every observation: with no uplink filter rule installed for the AP's
WAN producer, IPA has no rule telling it where an uplink packet should go, and
both directions of the modem data path stay unfinished.

### What was tried

Handlers were added for both ids that decode nothing and return
`QMI_RESULT_SUCCESS`.  They fire — `qmi config_req 1 flt_req 1`, no
`qmi unmatched` lines remain and no decode errors — and the data path is
**unchanged**: `ch_rp` still index 1 against `ch_wp` 47.

So acknowledging is necessary but not sufficient.  Stock does three things the
acknowledgement alone does not:

1. decodes the filter rule specs out of `INSTALL_FILTER_RULE_REQ`,
2. writes them into IPA's filter table for the AP's WAN producer pipe
   (`ipa3_install_fltr_rule` / `ipa3_wwan_register_to_ipa`), and
3. sends `QMI_IPA_FILTER_INSTALLED_NOTIF_REQ` back to the modem with the
   resulting filter handles.

A bare success response plausibly tells the modem that **zero** rules were
installed, which is not obviously better than silence.

## FOUND IT: mainline programs a GSI round-robin weight of zero

`gsi_channel_program()` in `drivers/net/ipa/gsi.c`:

```c
	u32 wrr_weight = 0;

	/* Command channel gets low weighted round-robin priority */
	if (channel->command)
		wrr_weight = reg_field_max(reg, WRR_WEIGHT);
	val = reg_encode(reg, WRR_WEIGHT, wrr_weight);
```

Downstream, `ipa3_setup_sys_pipe()` in `rmnet_ipa.c`'s sibling `ipa_dp.c`:

```c
	if (ep->client == IPA_CLIENT_APPS_CMD_PROD)
		gsi_channel_props.low_weight = IPA_GSI_MAX_CH_LOW_WEIGHT; /* 15 */
	else
		gsi_channel_props.low_weight = 1;
```

and `include/linux/msm_gsi.h` documents the field as

> `@low_weight: low channel weight (priority of channel for RE engine round
> robin algorithm); **must be >= 1**`

**Mainline programs 0 for every non-command channel.**  A zero weight starves
the channel in GSI's ring-engine round-robin scheduler.

The consistency check is what makes this convincing: across this entire
investigation the **only** channel that ever drained was channel 6, the AP
command channel — the one channel mainline gives a non-zero weight.

### Effect, measured

Setting the default weight to 1 (`wrr_weight = 1`), with nothing else changed:

```
before:  ch5 TX state 2  ch_rp ffff6010  ch_wp ffff62f0   id ... p1 k1 l1
after:   ch5 TX state 3  ch_rp ffff6030  ch_wp ffff6030   id f3 a3 c3 p3 k3 l3
                         qos 00000201                     ev2 hw_rp=3
```

* `ch_rp == ch_wp` — the uplink channel **drains completely** for the first
  time; previously the read pointer was frozen at index 1 forever.
* All three transactions complete (`p3 k3 l3`, was `p1 k1 l1`) and three
  events are posted and processed.
* `qos 00000201` = `WRR_WEIGHT` 1 with `USE_DB_ENG` set; the command channel
  reads `0000020f` (weight 15), matching downstream exactly.
* Channel 7 (the AP exception endpoint) also starts consuming buffers.
* `gsi_channel_stop()` now **succeeds** — state 3 (STOPPED) with the ring
  drained.  Stopping this channel used to hang, which is what wedged
  `ip link set rmnet_ipa0 down` throughout this port's history.

This single line explains the whole "IPA consumes exactly one transfer and
halts" signature, and it is invariant to every IPA-side knob precisely because
it was never an IPA problem — it was GSI scheduling.

### The next blocker, reproducibly

With uplink actually reaching the modem, the modem now crashes at data-call
setup, every time:

```
qcom-q6v5-mss 4080000.remoteproc: fatal error received:
    ipa_hal.c:2292:IPA Assert: !((ipa_hal.irq.irq_stts.value & ipa_cfg.hw.irq_enab
ipa 1e40000.ipa: received modem crashed event
ipa 1e40000.ipa: GSI command 2 for channel 8 timed out, state 4
ipa 1e40000.ipa: channel 8 global error ee 0x00000000 code 0x00000002
ipa 1e40000.ipa: error -11 attempting to stop endpoint 16
```

Note the last three lines: that is **exactly** the sequence the 2026-08-22
handoff opened with, and it appears here *immediately after* the modem crash
event.  That settles it — the `GSI_OUT_OF_BUFFERS` / stop-timeout signature is
fallout from a dead modem, never the cause.

The bearer still connects and yields a valid IPv6 /64, but IPA tears the modem
netdev down before traffic can be tested, so `ping` reports "Network
unreachable" and `rmnet_ipa0` has already disappeared.

### The crash is an SMMU translation fault, and the chain is fully traced

The modem assert is the *last* link, not the first.  Immediately before it:

```
[151.731188] arm-smmu 16c0000.iommu: Unhandled context fault:
             fsr=0x402 [Format=2 TF], iova=0x00000038, fsynr=0x2,
             cbfrsynra=0x18e0, cb=0, PLVL=2
[151.731286] ipa 1e40000.ipa: unexpected general interrupt 0x00000002
[151.732191] ipa 1e40000.ipa: microcontroller error event
[151.791247] qcom-q6v5-mss: fatal error received: ipa_hal.c:2292:IPA Assert...
[151.792174] ipa 1e40000.ipa: received modem crashed event
```

* `cbfrsynra = 0x18e0` is the IPA: `msm8998.dtsi` has
  `iommus = <&anoc2_smmu 0x18e0 0x0>` on the `ipa@1e40000` node.
* `fsr = 0x402`, Format=2 TF — a **translation fault**: IPA DMA'd to
  IOVA `0x00000038`, which has no mapping.
* GSI general interrupt `0x2` is bit 1 = `BUS_ERROR`, the GSI-side report of
  that same fault, at the same microsecond.

So the full chain is:

```
GSI channel finally runs (WRR fix)
  -> IPA DMAs to unmapped IOVA 0x38
  -> SMMU translation fault
  -> GSI BUS_ERROR general interrupt
  -> IPA microcontroller error event
  -> modem's IPA HAL asserts on its IRQ state
  -> modem crash
  -> GSI stop timeout / OUT_OF_BUFFERS on channel 8
```

That last line is the signature this whole investigation started from.  It is
five steps removed from the cause.

An IOVA of `0x38` is far too small to be a real DMA buffer; it looks like a
near-null pointer being dereferenced — a structure field IPA or its
microcontroller expects the AP to have populated.  The "microcontroller error
event" arriving in the same millisecond points at the uC shared memory area
(`IPA_MEM_UC_SHARED`, offset 0, size 0x80 — and `0x38` falls inside it).
Comparing mainline's `ipa_uc.c` initialisation of that area against stock's
`ipa3_uc_interface_init()` is the next concrete step.

Two things were retested **on top of the WRR fix**, because both earlier
negatives were taken when nothing was flowing and were therefore meaningless:

* disabling the uplink `ENDP_STATUS` (matching stock) — fault unchanged;
* the catch-all routing rule `ipa.def_rt_ep=18` — fault unchanged.

So the fault is not the status descriptor and not routing to pipe 0.  It
reproduces at exactly `iova=0x00000038` on every boot.  No imem/smem mapping
errors are logged, so IPA's IOMMU regions appear to be established; something
IPA touches once the uplink channel actually runs is simply not mapped.

### Stock runs the IPA's SMMU in stage-1 BYPASS

The downstream msm8998 IPA device tree node carries:

```
qcom,arm-smmu;
qcom,smmu-disable-htw;
qcom,smmu-s1-bypass;          <-- stage 1 bypass
```

and splits the streams into three separate context banks:

```
ipa_smmu_ap:   compatible = "qcom,ipa-smmu-ap-cb";   iommus = <&anoc2_smmu 0x18e0>;
ipa_smmu_wlan: compatible = "qcom,ipa-smmu-wlan-cb"; iommus = <&anoc2_smmu 0x18e1>;
ipa_smmu_uc:   compatible = "qcom,ipa-smmu-uc-cb";   iommus = <&anoc2_smmu 0x18e2>;
```

Mainline instead attaches both 0x18e0 and 0x18e2 to the single `ipa@1e40000`
node with a normal **translating** domain:

```
iommus = <&anoc2_smmu 0x18e0 0x0>, <&anoc2_smmu 0x18e2 0x0>;
```

With stage-1 bypass the IPA works in physical addresses; with a translating
domain every address it is handed is interpreted as an IOVA.  This is a real,
documented divergence from stock and is worth revisiting — **but it is
probably not the cause of this fault**, for a reason worth writing down:

*A mis-translated physical address would fault at a large address* (RAM on this
SoC starts around `0x80000000`), not at `0x38`.  `0x38` looks like a
**near-null base plus a small offset** — and notably `0x38 = 3 * 16 + 8`, i.e.
the second half of entry 3 in a ring of 16-byte elements whose base address is
**zero**.  GSI event ring entries are exactly 16 bytes
(`GSI_RING_ELEMENT_SIZE`).  That points at a ring whose base was never
programmed, rather than at address translation.

Two ways of forcing bypass were tried and **both failed to boot** (the phone
panicked and fell back to Android), so neither produced a usable result:

* `iommu.passthrough=1` on the command line — too broad, other masters need
  their mappings;
* deleting `iommus` from joan's `&ipa` node plus `arm-smmu.disable_bypass=0`.

Both changes have been reverted.  A per-device identity domain would be the
correct way to test this properly if it is revisited.

### The zero-base ring theory is also disproven

Every GSI ring the AP owns was read back from hardware:

```
ev0  state 1 len 4096 base 0000000ffffff000
ev1  state 1 len 4096 base 0000000fffffb000
ev2  state 1 len 8192 base 0000000fffff8000
ev3  state 1 len 4096 base 0000000fffff5000
hwch5 state 3 len 8192 base 0000000fffff6000
hwch6 state 2 len 4096 base 0000000fffffe000
hwch7 state 2 len 4096 base 0000000fffffa000
hwch8 state 4 len 4096 base 0000000fffff4000
```

No null base anywhere.  Note also that these are **36-bit IOVAs at the top of
the address space** (`0xf_ffff_x000`) — which means the `ch_rp`/`ch_wp` values
reported elsewhere in this document are only the low 32 bits of a 64-bit
address, and `0x38` is genuinely a tiny address rather than a truncation.

`hwch8 state 4` is `STOP_IN_PROC`, the stuck stop left behind by the modem
crash.

**Hard rule: the AP cannot read the modem's GSI execution environment**
(register block `+0x4000`).  This was tried twice — once unguarded, and once
guarded so that the read only happened while `modem_state` was RUNNING and
before any uplink.  **Both took the phone down.**  It is not a timing problem;
those registers are simply not readable from the AP on this SoC.  The probe has
been removed and should not be reintroduced.

That closes off the direct way of testing the most attractive remaining theory
for `iova=0x38` — that the modem's own event ring for its WAN consumer has a
null base, so GSI writes completion events at `0x00`, `0x10`, `0x20`, `0x30`…
and `0x38` falls inside entry 3.  The arithmetic fits (GSI events are 16 bytes)
but it cannot be confirmed by reading the modem's registers.  It would have to
be established indirectly.

So `iova=0x38` remains unexplained: it is not a mistranslated physical address,
not a null-base AP ring, and not the routing/status/filter configuration.  What
is left to look at is what IPA touches *at the moment the first uplink transfer
completes* — the uC interface and the modem's own descriptor handoff.

**Lesson worth carrying:** a negative result taken while the data path is dead
proves nothing.  Two candidate fixes were wrongly discarded that way in this
session, and one experiment (the misaligned rule) was structurally invalid.
Re-run anything that was tested before the WRR fix.

## Reverse-engineered rule formats, and what they rule out

Mainline has no rule-construction code at all, so the formats came from the
stock tree — `drivers/platform/msm/ipa/ipa_v3/ipahal/ipahal_fltrt_i.h`:

```c
struct ipa3_0_flt_rule_hw_hdr {      struct ipa3_0_rt_rule_hw_hdr {
	u64 en_rule:16;                      u64 en_rule:16;
	u64 action:5;                        u64 pipe_dest_idx:5;
	u64 rt_tbl_idx:5;                    u64 system:1;
	u64 retain_hdr:1;                    u64 hdr_offset:9;
	u64 rsvd1:5;                         u64 proc_ctx:1;
	u64 priority:10;                     u64 priority:10;
	u64 rsvd2:6;                         u64 rsvd1:5;
	u64 rule_id:10;                      u64 retain_hdr:1;
	u64 rsvd3:6;                         u64 rule_id:10;
};                                           u64 rsvd2:6;
                                     };
```

with `action` 0 = `IPA_PASS_TO_ROUTING`.

Decoding mainline's all-zero **"zero rule"** against those:

* as a *filter* rule it means "match everything, pass to routing table 0" —
  reasonable;
* as a *route* rule it means **`pipe_dest_idx = 0`**, and pipe 0 on msm8998 is
  `IPA_CLIENT_MHI_PROD`, a **producer**, not a valid consumer.

Since mainline never installs the modem's uplink filter rules, every uplink
packet falls through to that rule, so this looked like the answer.

A real catch-all routing rule was therefore implemented — the route table
entries now point at a properly encoded rule with `pipe_dest_idx` set and
`retain_hdr = 1`, in their own region so the filter tables keep referring to
the zero rule (the two rule types are encoded differently and cannot share an
entry array).  It is behind `ipa.def_rt_ep=<endpoint>`; `-1` keeps upstream
behaviour.

The first attempt at this was **invalid** and is worth recording as a trap:
the rule was placed 8 bytes into the allocation, but stock asserts that a
rule list in system memory is 128-byte aligned
(`IPA3_0_HW_TBL_SYSADDR_ALIGNMENT` is 127, in `ipahal_fltrt_i.h`), so the
hardware would not have parsed it.  Mainline's own comment says the same thing
about the zero rule but the code never has to honour it, because the zero rule
sits at offset 0.  The rule now gets its own aligned block.

A catch-all rule is just the 8-byte header: `ipa_rt_gen_hw_rule()` appends an
equation body only when the rule carries attributes, and `en_rule = 0` means
"match everything", so there is nothing to append.

**It changes nothing.**  With `def_rt_ep=18` (the modem's WAN consumer),
correctly encoded and correctly aligned, confirmed applied, with IPA setup and
the QMI handshake healthy — IPA still consumes exactly one TRE.

### The narrowing that matters

The AP's exception endpoint (`ep15` / channel 7) has **consumed zero buffers**
in every single run.  If IPA were processing uplink packets and merely failing
to route them, they would be exception-routed there.  They are not.

Combined with the routing-rule result, that places the stall **before the
routing stage** — in the source pipe / HPS side, not in routing and not at the
destination.  Everything downstream of the fetch has now been eliminated.

### The invariant

`ch_rp` sits at index 1 in **every** configuration tried:

| change | result |
|---|---|
| BEI on/off (runtime `ipa.tx_bei`) | 1 |
| uplink `ENDP_STATUS` disabled (with BQL bypassed, so visible) | 1 |
| `SRC_ACK_ENTRIES` set to stock 14/16 | 1 |
| `DST_DPS_DMARS` UL raised 1 → 3 | 1 |
| `ROUTE_DEF_PIPE` pointed at the modem | 1 |
| QMI CONFIG + INSTALL_FILTER_RULE acknowledged | 1 |
| catch-all routing rule installed | 1 |
| `HDR_ENDIANNESS` cleared on the uplink pipe, as stock leaves it | 1 |
| catch-all routing rule, correctly encoded **and** 128-byte aligned | 1 |

Each was confirmed applied by reading the register back, so these are real
negatives rather than changes that failed to land.  That invariance is the
strongest remaining clue: whatever holds the pipe is upstream of every knob
listed above.

## Start here next

The question is now narrow: **why does IPA stop fetching after one transfer, in
both directions?**  Both directions failing together points away from framing
and toward the AP↔modem data-plane binding.

1. **Implement the uplink filter rule path.**  This is the main piece of work
   and it is the one with a clear stock reference.  Decode
   `QMI_IPA_INSTALL_FILTER_RULE_REQ` (see
   `ipa_qmi_service_v01.h`, `QMI_IPA_INSTALL_FILTER_RULE_REQ_MAX_MSG_LEN_V01`
   is 22369, so the rule list is the bulk of it), install the rules into the
   AP's filter table, and reply with the filter handles, then send
   `QMI_IPA_FILTER_INSTALLED_NOTIF_REQ`.  Downstream's
   `ipa3_qmi_filter_request_send()`, `ipa3_wwan_register_to_ipa()` and
   `ipa3_install_fltr_rule()` in `rmnet_ipa.c` are the reference.
   Mainline currently writes only "zero rules" into its filter tables and
   relies on the modem to install everything, which evidently does not hold on
   msm8998.

   The `DST_DPS_DMARS` idea is **closed**: the UL group's single DMA resource
   was raised to 3, confirmed by readback (`dst2 3/3 ...`), and IPA still
   consumed exactly one.  There is also no wider `IPA_STATE_*` register set to
   mine — downstream's ipahal exposes only `IPA_STATE_AGGR_ACTIVE` for v3.x,
   and it reads 0.
2. **Check the QMI data-port/endpoint binding.**
   `qmicli --wda-get-data-format` fails with `QMI protocol error (48):
   InvalidArgument`, which on this modem generation usually means the WDA
   client must name an endpoint.  If ModemManager's endpoint binding does not
   match what the modem expects, neither direction would carry traffic — which
   is exactly what is observed.
   Largely done: `--wda-get-data-format="ep-type=embedded,ep-iface-number=1"`
   *does* answer, and reports `raw-ip` with `qmapv4` uplink **and** downlink —
   consistent with rmnet's `data_format 0000000d` and with IPA's MAPv4.  So the
   protocol negotiation is not obviously wrong.  It also reports
   `downlink data aggregation max datagrams 31` / `max size 63`; 63 bytes is
   not a plausible aggregate buffer against IPA's 8192-byte RX buffers, but the
   endpoint in that query was a **guess**, so confirm it against the endpoint
   ModemManager actually bound before treating it as a finding.
3. **Compare the INIT_MODEM_DRIVER payload with stock field by field.**  The
   handshake completes and the memory *map* matches stock, but the descriptors
   actually sent (`hdr_tbl_info`, `v4/v6_route_tbl_info`, `modem_mem_info`,
   `ctrl_comm_dest_end_pt`) were spot-checked and agree:
   `ctrl_comm_dest_end_pt` is 16, matching stock's `APPS_WAN_CONS` pipe;
   `modem_route_count` 8 gives `end = 7`, matching the DT's
   `v4_modem_rt_index_hi = 0x7`; and the 0x78-byte route region yields 15
   entries, matching `v4_rt_num_index = 0xf`.  What remains unchecked is the
   handful of optional hashed-table and stats fields.

## Instrument traps hit this session

Add these to the existing list in the 2026-08-22 handoff; each produced a
confidently wrong reading before being caught.

* **`netif_queue_stopped()` only tests `__QUEUE_STATE_DRV_XOFF`.**  It reported
  "0" (running) while the queue was in fact stopped by BQL via
  `__QUEUE_STATE_STACK_XOFF`.  Print the raw `txq->state`.
* **`q->q.qlen` is meaningless for `pfifo_fast`.**  It is a lockless qdisc whose
  backlog lives in per-CPU counters, so it reads 0 however full it is.  Use
  `qdisc_qlen_sum()`.  This one cost a whole build/boot cycle by making a
  10-packet backlog look like an empty queue.
* **A `str.replace()` patch script that prints success unconditionally.**  If
  the pattern does not match, nothing changes and the log still says "patched".
  Assert the pattern is present before replacing, and confirm the new strings
  are in `vmlinux` before booting.
* **Bearer index is not stable.**  `mmcli -m 0` exposes an *initial* EPS bearer
  at `/Bearer/0` that reports `connected: yes`; the connected data bearer is a
  different index.  Read `modem.generic.bearers.value[N]`.
* **`rc-service modemmanager restart` can leave orphans.**  OpenRC loses the
  PID, reports "already stopped", and the survivor holds the D-Bus name, so a
  fresh instance exits with "could not acquire the
  'org.freedesktop.ModemManager1' service name" and `mmcli` sees no modem.
  `pkill -x ModemManager` first.

## Where the instrumentation lives

Branch `joan/gsi-tx-bei-diag` in the kernel worktree
(`~/vibe-coding-projects/coding/linux-mainline-v30-usb-otg`), **uncommitted**,
on top of `ca2f77f89`.  It adds:

* `/sys/bus/platform/devices/1e40000.ipa/gsi_dbg` — software counters for the
  whole GSI path plus live register readback, per-channel TRE/event ring
  indices, channel RP/WP, `ipa_start_xmit()` outcomes by reason, and the netdev
  queue and qdisc state.  Writing `zero`, `napi <ch>` or `dbell <ch>` runs a
  command.
* `/sys/bus/platform/devices/1e40000.ipa/ipa_dbg` — IPA IRQ registers and, per
  endpoint, `ENDP_INIT_CTRL` / `_CFG` / `_MODE` / `_SEQ` / `ENDP_STATUS` /
  `_RSRC_GRP`.
* `ipa_dbg` also reports the QMI handshake milestones
  (`work`/`rsp`/`ind_reg`/`drv_cmplt`/`bye`/`send_ret` plus the readiness
  flags), `setup_complete`/`uc_loaded`/`modem_state`, and every
  `SRC_/DST_RSRC_GRP_*` limit read back from hardware.
* `/sys/module/ipa/parameters/tx_bei` — runtime toggle for the TX BEI flag.
* `/sys/module/ipa/parameters/bql` — disables byte-queue-limits accounting, so
  the ring keeps being fed with no completions.  Pair it with
  `echo bqlreset > gsi_dbg`, which calls `netdev_tx_reset_queue()` to clear the
  latched XOFF.  Toggle at runtime only; see the warning above.
* Two `JOAN-RMNET` log lines reporting the rmnet aggregation config and
  `data_format` as userspace sets them.

Every counter is incremented on *entry* to the path it names, so "never
reached" is distinguishable from "reached and succeeded", and nothing is rate
limited.

## VoLTE and calls — first real signal now that data works

With the data path up, the voice picture is much clearer than the
"QMI error 90 IncompatibleState" the previous handoff recorded.

**The network offers VoLTE to this device.**  `qmicli --nas-get-system-info`:

```
LTE service:
        Domain: 'cs-ps'
        Voice support: 'no'          <- no CS fallback, as expected on T-Mobile
        IMS voice support: 'yes'     <- VoLTE is available
        Registration restriction: 'unrestricted'
```

**The modem is already configured to prefer packet-switched voice.**
`qmicli --voice-get-config`:

```
Current Voice Domain Preference: 'ps-preferred'
```

**A call now dials.**  Driving the ModemManager call object over D-Bus (see the
tooling note below), a call to the carrier's own automated line goes

```
state=1 (DIALING) ... state=7 (TERMINATED)
```

That is a real change: the modem accepts the dial and attempts the call rather
than refusing it outright.  It does not reach ACTIVE, which is consistent with
the IMS stack not being registered.

### Bringing the IMS PDN up by hand does not work

`qmicli --wds-start-network="apn=ims,ip-type=6"` is rejected:

```
error: invalid ip family value given: '6'
error: couldn't start network: QMI protocol error (70): 'InvalidOperation'
[qrtr://0] Client ID not released:  Service: 'wds'  CID: '1'
```

Two things to note: the ip-type spelling libqmi wants here is not `6`, and the
attempt **leaks a WDS client ID** which disturbs the active bearer — data stops
passing afterwards.  Do not run this against a live connection.

With that attempt in place the call behaved differently: it stayed in
**DIALING for the full 20 s sample** instead of terminating after ~9 s.  Still
never ACTIVE.

### What is still missing

IMS registration on this modem lives entirely in the **proprietary QMI services
701-707 and 800** (version 2, instance 1, on the modem's QRTR node).  None of
the standard IMS service ids (IMSP/IMSVT/IMSA, 31/32/33) are present, and
libqmi implements none of the 700-range.  So VoLTE needs those services
reverse-engineered and driven — that remains the substantial piece of work.

Note also that **libqmi 1.39 has no voice dial at all** — `qmicli --help-voice`
offers only `--voice-get-config`, `--voice-get-supported-messages` and
`--voice-noop`, and the modem rejects get-supported-messages with
`InvalidQmiCommand`.  Calls therefore have to be driven through
ModemManager.

### Talking to the IMS services directly

Since libqmi implements none of the 700-range, the only way in is raw QMI over
QRTR.  A small static aarch64 probe was written for this
(`imsprobe.c`, kept alongside the patch in
`~/.ember/workspace/joan-cellular-2026-08-23/`).  The essentials:

* `socket(AF_QIPCRTR /* 42 */, SOCK_DGRAM, 0)`, address is
  `struct sockaddr_qrtr { unsigned short sq_family; __u32 sq_node; __u32 sq_port; }`.
* Service messages carry the 7-byte QMI header only — no QMUX wrapper:
  `struct { u8 flags; u16 txn; u16 msg_id; u16 len; } __packed`
  with `flags = 0` for a request.
* Address the service by the node/port `qrtr-lookup` reports.  On joan:
  701→0:70, 702→0:72, 703→0:73, 704→0:69, 705→0:71, 706→0:75, 707→0:74,
  800→0:67.
* `msg_id 0x001E` is the standard QMI *get supported messages*, which most
  services implement and which enumerates their message ids — the natural
  first step for identifying which of 701-707 is IMSA (registration status)
  and which is IMSS (VoLTE enable).

Cross-compile with `aarch64-linux-gnu-gcc -static`; a static glibc binary runs
fine on the Alpine/musl rootfs.

### What the probe established

All eight services answer.  Every one replies to any message id with the
standard result TLV:

```
TLV 0x02 len 4 : 01 00 39 00      result = FAILURE, error = 0x39 (57)
```

Service **704 (port 69) is silent** — it does not answer at all, unlike the
other seven.  That difference is worth following up.

A blind sweep of message ids `0x0000`-`0x00ff` on every service returns that
same error for *all* 256 ids, which means the sweep cannot discriminate: an
empty request fails validation on any message that has mandatory TLVs, so
everything answers identically.  **Do not repeat the blind scan** — it cannot
work without knowing the TLV layout first.

(The scanner `imsscan.c` is kept with the patch; note its "skip the boring
answer" filter had the result/error byte offsets wrong — the result is at
payload offset 3 and the error at offset 5, i.e. `buf[10]` and `buf[12]` of the
whole datagram.)

### CORRECTION: the 700-range services are not IMS, and IMS is AP-side

The 2026-08-22 handoff recorded that "the modem *does* carry an IMS stack —
`qrtr-lookup` lists proprietary services **700-707 and 800**", and concluded
VoLTE was a matter of reverse-engineering those.  **That is wrong**, and the
stock ROM proves it.

LG's own `/system/vendor/lib64/libqmiservices.so` defines the IMS services and
each `*_qmi_idl_service_object_v01` carries its service id at offset +8:

| symbol | service id |
|---|---|
| `imss` (IMS Settings) | 0x12 = **18** |
| `ims_qmi` | 0x13 = **19** |
| `imsp` (IMS Presence) | 0x1f = **31** |
| `imsvt` (IMS Video Telephony) | 0x20 = **32** |
| `imsa` (IMS Application, registration status) | 0x21 = **33** |
| `imsrtp` | 0x28 = **40** |

Those are the *standard* QMI service ids.  On joan, `qrtr-lookup` reports
services 1-71 plus 701-707 and 800 — and **18, 19, 31, 32, 33 and 40 are not
among them.**  The IMS services simply are not registered.  Whatever 701-707
and 800 are, they are not the IMS stack.

Dumping the service id out of **every** `*_qmi_idl_service_object_v01` in that
library gives LG's complete QMI service table — 37 services, ids 1 to 227:

```
  1 wds     2 dms     3 nas     4 qos    5 wms    7 auth   8 at     9 voice
 10 cat    11 uim    12 pbm    17 sar   18 imss  19 ims_qmi
 26 wda    29 csvt   31 imsp   32 imsvt 33 imsa  34 coex  36 pdc   40 imsrtp
 41 rfrpe  42 dsd    43 ssctl  46 atp   47 dpm   48 dfs   50 uim_remote
 56 lowi   61 sfs    67 blm    68 ott   70 lte   71 uim_http  74 antswitch
227 svs
```

**Nothing in the 700 range exists.**  So 701-707 and 800 are not QMI services
with vendor IDL definitions at all, and were never the IMS stack — QRTR also
carries non-QMI protocols.  Probing them for IMS was chasing the wrong thing.

*Correction to an earlier draft of this document:* it claimed the IMS services
must be AP-provided "because `libqmiservices.so` is an AP-side library".  That
reasoning is **invalid** — the same library defines `wds`, `dms` and `nas`,
which the modem obviously provides.  A client-side IDL says nothing about who
registers the service.  What is actually established is narrower:

* IMS services 18/19/31/32/33/40 are **absent from QRTR** on joan, and stay
  absent with data up and settled for 150 s;
* the stock system image contains **no IMS executable at all** — a search of
  every `bin` directory finds none;
* the IMS stack in this build is HIDL and Java:

```
/system/system_ext/lib64/com.qualcomm.qti.imscmservice@2.{0,1,2}.so
/system/system_ext/lib64/vendor.qti.hardware.radio.ims@1.{0..6}.so
/system/system_ext/framework/com.qualcomm.qti.imscmservice-V2.x-java.jar
/system/system_ext/etc/permissions/com.qualcomm.qti.imscmservice*.xml
```

i.e. it lives inside Android's framework.

i.e. it lives inside Android's framework, with no standalone daemon to port.

### The modem is fully provisioned for VoLTE — so the gap is on our side

The remaining ambiguity ("does the modem provide IMS but has not started it?")
is settled by the modem's own carrier configuration.  PDC (service 36) is
registered and libqmi speaks it:

```
$ qmicli -d qrtr://0 --pdc-list-configs=software
Total configurations: 7
Configuration 1:  Description: TMO              Status: Active
Configuration 2:  Description: Commercial-US_Cellular   Status: Inactive
Configuration 3:  Description: hVoLTE-Verizon   Status: Inactive
...
$ qmicli -d qrtr://0 --pdc-list-configs=platform
Total configurations: 0
```

The **T-Mobile carrier config is already active**, and these MBNs plainly do
carry VoLTE policy (one of them is literally named `hVoLTE-Verizon`).  So on
the modem side everything needed for VoLTE is in place:

* correct carrier config active (`TMO`),
* network advertises `IMS voice support: yes`,
* voice domain preference is `ps-preferred`,
* a working data bearer.

And it still registers **zero** IMS QMI services.  A modem-provided service
would appear on the bus regardless of what the applications processor does.
It follows that services 18/19/31/32/33/40 are **not provided by the modem** —
they are provided by the applications processor, which on stock is Android
userspace (HIDL + framework, with no standalone daemon to port).

**Conclusion: VoLTE on joan requires implementing the AP-side IMS stack** —
registering those QMI services and the IMS/SIP client behind them — on a Linux
userspace.  It is not a modem configuration problem and not a modem
reverse-engineering problem.  The call reaching DIALING and stopping is exactly
what that looks like: the modem is willing, nothing on our side registers with
IMS.

This is also why VoLTE remains broadly unsolved on mainline Linux phones, and
it means goals "verify VoLTE" and "verify phone calls" cannot be closed by
further work on the modem or the kernel.

### The two preconditions for an AP-side IMS client are present

That path is viable rather than theoretical — both things such a client would
need are already in place on this device:

**1. The SIM carries an ISIM.**  `qmicli --uim-get-card-status`:

```
Application [1]:  Application type: 'usim (2)'   state: 'ready'
Application [2]:  Application type: 'isim (5)'   state: 'detected'
```

So IMS AKA credentials exist and a Linux-side client can authenticate against
the IMS core (via `QMI_UIM` authenticate against the ISIM, rather than having
to fake anything).

**2. The IMS APN is provisioned as a modem profile.**
`qmicli --wds-get-profile-list=3gpp`:

```
 [1] APN: 'fast.t-mobile.com'   PDP type: 'ipv6'   context 1
[10] APN: 'ims'                 PDP type: 'ipv6'   context 10   APN disabled: 'no'
```

So the IMS PDN does not need inventing — bring up **profile index 10**.  Note
the earlier failed attempt used `--wds-start-network="apn=ims,ip-type=6"`,
which is the wrong spelling and leaks a WDS client id; use the profile index
instead, and not against a live bearer.

**Shape of the remaining work, then:** a userspace IMS client on the AP that
brings up profile 10, performs SIP REGISTER with IMS AKA against the ISIM, and
handles SIP/RTP for calls — with the modem contributing the bearer and the
`voice` service (9) for call control.  Every precondition below it is now
verified working: data path, carrier config, ISIM, IMS APN, network IMS
support.

This closes off the path the previous handoff pointed at, and should stop the
next session spending time probing 701-707.

### Where the message definitions actually are

The definitions are proprietary, so the reference has to come from the stock
ROM: LG's Android system image on the device's own partitions carries the IMS
QMI client libraries.  Extracting the message ids and TLV layouts from those is
the concrete next step, and it is the same trick already used successfully in
this port for the modem and IPA firmware (`mount -o ro
/dev/disk/by-partlabel/...`).

Also worth checking before that: IMS registration did **not** happen on its own
after 150 s of settled, working data — so this is not a timing problem, the
modem genuinely is not being told to register.

### Tooling trap

`mmcli` 1.25.95 in this rootfs **segfaults** when a call object is addressed
(`mmcli -c <path>` or `-c <index>`), and `--voice-create-call` only creates the
object — it does not dial.  Drive calls over D-Bus instead:

```sh
P=$(mmcli -m 0 --voice-create-call="number=..." | grep -o '/org/.*/Call/[0-9]*')
gdbus call --system --dest org.freedesktop.ModemManager1 --object-path "$P" \
        --method org.freedesktop.ModemManager1.Call.Start
gdbus call --system --dest org.freedesktop.ModemManager1 --object-path "$P" \
        --method org.freedesktop.DBus.Properties.Get \
        org.freedesktop.ModemManager1.Call State
```

`Call.Start` returns "Timeout was reached" even when the dial succeeds; read the
`State` property rather than trusting the method return.

**Restarting ModemManager tears down the data bearer** and can leave the daemon
unable to talk to the modem for a while ("couldn't create manager: Timeout was
reached").  Do not restart it casually once data is up.

Call audio remains separately blocked: the earpiece does not work (see the
2026-08-22 handoff), so a connected call would need loudspeaker or headphones.

## Previously: VoLTE and calls

Unchanged and still behind working data.  Confirmed again this session that the
modem exposes proprietary QMI services **701–707 and 800** (version 2,
instance 1) alongside the standard Voice service (9).  libqmi implements none of
the 700-range, so VoLTE remains reverse-engineering work.

---

## VoLTE media path: SETTLED — modem vocoder (CVD), not AP-side RTP

This was the open question blocking any VoLTE plan. It is now answered from the
stock ROM and the downstream kernel. It is **not** AP-side RTP.

### Evidence

**1. Stock audio HAL drives a CVD voice session, not a PCM stream.**
`/system/vendor/lib64/hw/audio.primary.msm8998.so` contains:

    voice_start_call   VOICEMMODE   VSID   cvd_version   VOLTE

`voice_start_call` + VSID selection is the Qualcomm Core Voice Driver (CVD)
entry path. A userspace-RTP design would open an ordinary PCM stream instead.
(The numeric VSID constants show 0 byte-occurrences in the .so — they are ARM64
immediates, not stored words. The symbol names are the evidence, not the search.)

**2. VoLTE reuses the CS-call routing, with only the VSID differing.**
`mixer_paths_tavil.xml` has `voice-call *` paths (speaker, headphones, bt-sco,
afe-proxy, …) and **no separate VoLTE/RTP path**. Downstream confirms the
discriminator is the session id alone:

    q6voice.h:1814  #define VOLTE_SESSION_VSID   0x10C02000
    q6voice.h:1818  #define VOICEMMODE1_VSID     0x11C05000
    q6voice.h:1819  #define VOICEMMODE2_VSID     0x11DC5000

`VOIP_RX` / `voice_extn_compress_voip_*` also exist, but that is the separate
*non-IMS* VoIP use case — not the VoLTE path.

**3. The `imsrtp` QMI service (40) hint was correct.** The modem owns RTP.

### What this means

The AP's job during a VoLTE call is: open a CVD voice session on the Q6
(services **MVM**, **CVS**, **CVP** — Multimode Voice Manager / Core Voice
Stream / Core Voice Processor), then route PCM between the AFE and the codec.
Vocoding and RTP happen on the modem. Consequently:

* No AP-side vocoder, jitter buffer, or RTP stack is needed.
* But a **kernel voice driver is needed**, and it does not exist.

### Mainline gap (the real finding)

`sound/soc/qcom/` in the mainline tree has **zero** matches for
`q6voice|cvd|vsid|voicemmode|voice_mmode`. The qdsp6 stack is
q6asm/q6afe/q6adm/q6routing (+ q6apm/q6prm for AudioReach) — all data-path
audio. There is no voice session support **for any Qualcomm device**, not just
joan. Downstream carries it as:

    sound/soc/msm/qdsp6v2/q6voice.c        8841 lines / 230 KB
    sound/soc/msm/qdsp6v2/q6voice.h        52 KB
    sound/soc/msm/qdsp6v2/msm-pcm-voice-v2.c

So VoLTE audio is an *unimplemented mainline feature*, not a joan porting task.

### Why this is tractable anyway

The APR bus infrastructure mainline already has **works on joan today** — that
is how the Quad DAC audio came up. Downstream registers the voice services by
plain name:

    apr_register(... "MVM" ...)  apr_register(... "CVS" ...)  apr_register(... "CVP" ...)

Mainline binds APR services from device tree, so MVM/CVS/CVP are three
additional APR clients on the bus q6asm/q6afe already ride. The 8841-line
downstream file is large because it spans every SoC generation plus DTMF,
host-PCM, sound-focus and widevoice extras; a single-SoC session-setup +
PCM-front-end subset is a small fraction of that.

### Consequence for packaging

This splits the VoLTE work cleanly in two, and only one half is a pmOS package:

| Layer | Where it lives | Device-neutral? |
|---|---|---|
| CVD voice session (MVM/CVS/CVP) + PCM voice front-end | **kernel**, `sound/soc/qcom/qdsp6/` | yes — all Qualcomm |
| IMS daemon: QMI + ISIM AKA + SIP registration, call control | **userspace**, pmOS package | yes — any QRTR modem |

The kernel half cannot ship as an APKBUILD. The userspace half can, and should
stay device-neutral so it can graduate to pmaports.

---

## Writing the missing piece: `q6voice`, a mainline CVD client

Branch `joan/q6voice-mvm-probe` (off `master`, which carries the audio DT).

### Why this is smaller than the 8841-line downstream file suggests

Mainline already has everything underneath:

* **The APR bus works on joan today** — it is what carries q6asm/q6afe/q6adm,
  i.e. how the Quad DAC came up.
* **The service IDs are already in mainline's DT bindings.**
  `include/dt-bindings/soc/qcom,apr.h` declares

      APR_SVC_ADSP_MVM  0x09
      APR_SVC_ADSP_CVS  0x0A
      APR_SVC_ADSP_CVP  0x0B

  matching downstream's `APR_SVC_ADSP_*` byte for byte. The bindings were
  upstreamed; only the drivers never were.
* `struct apr_hdr`, `APR_SEQ_CMD_HDR_FIELD`, `apr_send_pkt()` all exist.

So the work is a new APR client, not new bus plumbing.

### RE findings that shaped the code

**Sessions are named with an ASCII string, not a numeric VSID.** The VSID
appears in the packet as its *hex spelling*:

    VOICEMMODE1_VSID_STR  "11C05000"
    VOICEMMODE2_VSID_STR  "11DC5000"

`voice_create_mvm_cvs_session()` selects the session by `strlcpy()`ing one of
those (or a legacy literal like `"default volte voice"` / `"default modem
voice"`) into a 20-byte `char name[SESSION_NAME_LEN]` payload. Passing the
numeric VSID would be wrong.

**Modem-borne calls create a PASSIVE control session, not a full one.**

    VSS_IMVM_CMD_CREATE_PASSIVE_CONTROL_SESSION  0x000110FF
    VSS_IMVM_CMD_CREATE_FULL_CONTROL_SESSION     0x000110FE

Full control is for VoIP, where the AP owns the vocoder. For CS and VoLTE the
modem drives the state machine, so the AP takes the passive session — matching
the finding above that media never reaches the AP.

**The new session's handle returns as the APR source port** of the
`APR_BASIC_RSP_RESULT` response, not in the payload.

### Opcode set recovered (enough for a call)

    VSS_IMVM_CMD_CREATE_PASSIVE_CONTROL_SESSION   0x000110FF
    VSS_IMVM_CMD_CREATE_FULL_CONTROL_SESSION      0x000110FE
    VSS_IMVM_CMD_ATTACH_STREAM                    0x0001123C
    VSS_IMVM_CMD_DETACH_STREAM                    0x0001123D
    VSS_IMVM_CMD_ATTACH_VOCPROC                   0x0001123E
    VSS_IMVM_CMD_DETACH_VOCPROC                   0x0001123F
    VSS_IMVM_CMD_START_VOICE                      0x00011190
    VSS_IMVM_CMD_STOP_VOICE                       0x00011192
    VSS_IMVM_CMD_SET_POLICY_DUAL_CONTROL          0x00011327
    VSS_ISTREAM_CMD_CREATE_PASSIVE_CONTROL_SESSION 0x00011140
    VSS_ISTREAM_CMD_CREATE_FULL_CONTROL_SESSION   0x000110F7
    VSS_ISTREAM_CMD_SET_MEDIA_TYPE                0x00011186
    VSS_ISTREAM_CMD_ATTACH_VOCPROC                0x000110F8
    VSS_IVOCPROC_CMD_CREATE_FULL_CONTROL_SESSION_V2 0x000112BF
    VSS_IVOCPROC_CMD_ENABLE                       0x000100C6
    VSS_IVOCPROC_CMD_DISABLE                      0x000110E1

### What is written so far

`sound/soc/qcom/qdsp6/q6voice.c` (275 lines) — registers all three services as
APR drivers, and creates an MVM passive session for VOICEMMODE1 on demand via
`/sys/kernel/debug/q6voice/create_session`, reporting the handle at
`mvm_handle`. Plus `CONFIG_SND_SOC_QDSP6_VOICE`, a Makefile entry, and
`service@9/a/b` nodes in `msm8998.dtsi`.

Build status: `q6voice.o` compiles clean; joan DTB rebuilds clean and the three
nodes are present in the decompiled output.

### The milestone this is aimed at

Not a call — one question: **does mainline's APR reach CVD at all?** If the
ADSP answers the create with a handle, the whole approach is validated and the
rest is filling in the sequence (CVS create → attach stream → CVP create →
enable → attach vocproc → start voice). If it times out, the ADSP firmware on
this device may not expose voice services to the AP, which would be a hard
stop worth knowing early.

### First boot attempt: two rig traps, both worth recording

The driver built and the DTB carried the nodes, but the first on-device run
bound nothing. Neither cause was in the driver.

**1. Modules installed after boot are not loaded by udev.** A freshly built
kernel has a new vermagic, so none of the rootfs's existing modules match.
Installing the new module tree over ssh *after* the phone is already up leaves
everything unloaded — udev's coldplug already ran. `modprobe` by hand works for
one module but not for the dependency web that normally comes up at boot.
Install modules, then reboot; do not install and test in the same boot.

**2. A config that builds the audio stack can still leave the ADSP dead.**
The config inherited from the GPU test tree had

    CONFIG_SND_SOC_QDSP6=m
    CONFIG_QCOM_APR=m
    # CONFIG_QCOM_Q6V5_PAS is not set     <-- silently absent

`QCOM_Q6V5_PAS` is the remoteproc driver that actually *boots* the ADSP. Without
it every audio module loads happily and nothing works: no remoteproc entries, no
APR devices, no sound cards. The symptom looks like a driver bug and is not one.

Diagnosis was: `/sys/class/remoteproc/` empty, the only glink channels being
`rpm_requests`/`glink_ssr` (the RPM edge, not the ADSP), and `/proc/asound/cards`
absent. This is the same shape as the earlier lesson that **absence of a
declaration is not the value zero** — an unset config symbol is not a default,
it is a missing driver.

Rebuilt against `docs/master-47041183b.config`, which carries
`CONFIG_QCOM_Q6V5_PAS=m` along with the IPA/RMNET/QRTR modem stack.

Rig note: `/sys/bus/aprbus/`, not `/sys/bus/apr/` — mainline names the bus
`aprbus`, so a check for the latter reports "no apr bus" even on a healthy
system.

---

## *** MAINLINE APR REACHES CVD — MVM SESSION CREATED ***

The milestone is met. On joan, with the `q6voice` driver:

    [17.527] qcom,apr ...apr_audio_svc: Adding APR/GPR dev: aprsvc:service:4:9
    [17.642] qcom,apr ...apr_audio_svc: Adding APR/GPR dev: aprsvc:service:4:a
    [17.666] qcom,apr ...apr_audio_svc: Adding APR/GPR dev: aprsvc:service:4:b
    [19.190] qcom-q6mvm aprsvc:service:4:9: q6voice: service bound (svc 0x09 domain 0x04)
    [19.192] qcom-q6cvs aprsvc:service:4:a: q6voice: service bound (svc 0x0a domain 0x04)
    [19.193] qcom-q6cvp aprsvc:service:4:b: q6voice: service bound (svc 0x0b domain 0x04)
    [56.431] qcom-q6mvm: q6voice: rsp op 0x000110ff status 0x00000000 handle 0x0020
    [56.431] qcom-q6mvm: q6voice: MVM session "11C05000" created, handle 0x0020

`bound` mask = 7: all three services attached. The ADSP answered
CREATE_PASSIVE_CONTROL_SESSION with **status 0** and issued handle **0x20**.

Two things this proves:

1. Mainline's APR bus reaches the Core Voice Driver. No new bus work is needed —
   the services enumerate on the same `apr_audio_svc` glink channel as
   q6core/q6afe/q6asm/q6adm.
2. The RE was right on both counts that could have silently failed: the ASCII
   session name (`"11C05000"`, not the numeric VSID) and the PASSIVE opcode.

Note the session was created on a boot with **no sound card registered**
(`/proc/asound/cards` empty). The voice control plane is independent of the
machine driver — useful, because it means session work can proceed in parallel
with codec routing work.

## Earpiece topology: RESOLVED (answers the 2026-08-21 open question)

The 08-21 handoff asked: *"does the V30 earpiece hang off WCD `EAR`, or is
every output behind ES9218P / TFA98xx?"* and noted the stock
`mixer_paths_*.xml` would settle it. It does:

    <path name="handset" />
    <ctl name="RX0 Digital Volume" value="84" />
    <ctl name="EAR PA Gain" value="G_6_DB" />

**The earpiece is on the WCD codec's EAR PA, fed by RX INT0.** Not behind the
ES9218P, not behind the TFA98xx. The codec's analog output block is real and
used on this board — just only for the earpiece.

`RX0 Digital Volume = 84` is a direct confirmation of the S8_TLV lesson: 84 is
0 dB on that control, not a large boost, and 0 would be silence.

So the joan audio topology is now fully mapped:

| Output | Part | State |
|---|---|---|
| Headphones / Quad DAC | ES9218P on QUAT_MI2S | **working** |
| Speaker | TFA98xx | probes, not yet heard |
| **Earpiece** | **WCD9340 EAR PA via RX INT0** | **not yet driven** |
| Mic (call) | WCD9340 — `voice-call-handset-mic`, `voice-call-submic1..3` | not yet up |

### Why this matters for calls

The earpiece is *the* default output for a handset call, so it is not a side
quest — it is on the critical path for phone calls, and the same WCD analog
bring-up serves both. Likewise the mic: stock has dedicated
`voice-call-handset-mic` and three sub-mic paths.

One important distinction: the call mic path is **not** a userspace ALSA
capture stream. CVP wires an AFE Tx port straight into the vocoder, so the
requirement is "codec Tx routed to an AFE port", not "arecord works". The
prerequisites overlap (the WCD must be up) but they are not the same milestone.

---

## *** A VOICE SESSION RUNS ON MAINLINE ***

The whole CVD bring-up sequence now completes on joan, every step status 0:

| # | Service | Opcode | Command | Result |
|---|---|---|---|---|
| 1 | MVM | `0x000110ff` | CREATE_PASSIVE_CONTROL_SESSION | status 0, handle `0x0020` |
| 2 | CVS | `0x00011140` | CREATE_PASSIVE_CONTROL_SESSION | status 0, handle `0x0100` |
| 3 | MVM | `0x0001123c` | ATTACH_STREAM (CVS handle) | status 0 |
| 4 | CVP | `0x000112bf` | CREATE_FULL_CONTROL_SESSION_V2 | status 0, handle `0x0100` |
| 5 | CVP | `0x000100c6` | ENABLE | status 0 |
| 6 | MVM | `0x0001123e` | ATTACH_VOCPROC (CVP handle) | status 0 |
| 7 | MVM | `0x00011190` | **START_VOICE** | **status 0** |

Mainline Linux has never had this. The Q6 voice path is up.

### The one real failure along the way, and what it taught

Step 5 initially returned **ADSP error 1**. The vocproc had been created with
`VSS_IVOCPROC_PORT_ID_NONE` and `TOPOLOGY_ID_NONE` — deliberately, to exercise
the control path without depending on codec routing.

**The ADSP will create a portless vocproc but will not enable one.** Supplying
real ports fixed it with no other change:

    rx_port     = 0x4000  (AFE SLIMBUS_0_RX)
    tx_port     = 0x4001  (AFE SLIMBUS_0_TX)
    rx_topology = 0x00010F77  (VSS_IVOCPROC_TOPOLOGY_ID_RX_DEFAULT)
    tx_topology = 0x00010F71  (VSS_IVOCPROC_TOPOLOGY_ID_TX_SM_ECNS)

The ports must be real *before any audio flows through them*. Note these are
SLIMbus port 0 — the WCD codec, i.e. the same path the earpiece and call mic
sit on. The session and the codec bring-up meet exactly here.

### Protocol details confirmed on hardware

* A create's response carries the new handle in the APR **source port**; every
  later command for that session goes to it as **destination port**. The reply
  to a create is what tells you where to send everything after it.
* `0x000100be` arrives before `0x000110e8` on MVM commands — an ACCEPTED event
  ahead of the basic result. Only the latter carries status.
* CVS and CVP independently issued handle `0x0100`. Handles are per-service, not
  global; they must not be compared across services.

### Known gap

Module unload does not destroy ADSP-side sessions. The ADSP keeps them, and a
later create for the same VSID goes **unanswered** (not refused — no response at
all, so it presents as a timeout). Until teardown is implemented, reload needs a
reboot in between. This cost one confusing cycle: an identical command that had
just succeeded timed out purely because the previous session was still alive.

### What this does and does not mean

It does **not** mean VoLTE or phone calls work. It means the kernel-side voice
path — the piece mainline was missing entirely — now exists and runs. Still
required for an actual call:

1. **Audio through the path.** SLIMbus/WCD bring-up so the earpiece and call mic
   are live. Same work as the earpiece issue.
2. **Call setup.** An AP-side IMS/SIP stack, per the earlier finding that joan's
   modem exposes zero IMS QMI services.
