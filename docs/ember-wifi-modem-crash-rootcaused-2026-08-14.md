# Wi-Fi modem crash root-caused and fixed: channel 169 (5845 MHz)

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-14

Closes the open item from
`ember-wifi-modem-crash-characterisation-2026-08-14.md`. Runs
`SCANFLAG-20260815T0318xxZ`, `CHAN169-20260815T032818Z`,
`CHAN169V2-20260815T033651Z`. RAM boots only; `rmtfs` read-only; no
association, pairing, registration, provisioning write or transmission.
Nothing written outside tmpfs; no partition flashed.

## 1. Root cause

Scanning **channel 169 (5845 MHz)** makes the WCN3990 firmware take a fatal
exception, which takes the modem down with it:

```
qcom-q6v5-mss 4080000.remoteproc: fatal error received:
    err_qdi.c:450:EX:wlan_process:1:WLAN RT:1075:PC=b01c4d3c
remoteproc remoteproc0: crash detected in 4080000.remoteproc: type fatal error
ath10k_snoc 18800000.wifi: firmware crashed!
```

That is the same signature, to the byte, as every crash recorded in this
port.

**It is *not* the same bug as msm8998-mainline #26/#27, and an earlier claim
of mine that it "matches issue #27" was wrong.** Those two report
`PC=b00bfa9c` on firmware 1.0.0.483, triggered by disconnecting (#26) and by
connecting (#27); this one is `PC=b01c4d3c` on firmware 1.0.0.695, triggered
by a scan. They share `err_qdi.c:450` and the `wlan_process` / `WLAN RT`
task only because that line is the firmware's generic exception reporter --
the reporting path, not the identity of the fault. The faulting PC is the
identity, and the two differ.

That also answers "was this ever flagged?". The modem-crash *family* on
MSM8998 has been open since May 2022 (#26 and #27, both still open), but the
scan trigger does not appear in either, and no report of channel 169 or
5845 MHz was found. It is easy to see why it stayed buried: when every
connect and every disconnect crashes the modem, nobody isolates an
additional per-scan crash underneath that, and isolating it needs WMI
tracing plus per-channel scan control.

The Hexagon disassembly of `PC=b01c4d3c` is `r2 = memw(r3+r2<<#0)` -- an
indexed load. That is what indexing a channel table with no entry for
5845 MHz looks like, not an assertion.

## 2. How it was isolated

The WMI trace was the turning point. A full scan walks channels in pairs and
dies 94 ms after the last pair:

```
... exit 5700 / exit 5720 / bss channel 5700
qcom-q6v5-mss: fatal error received: ...WLAN RT:1075:PC=b01c4d3c
```

That looked like the UNII-2e -> UNII-3 boundary, and it was wrong. What
actually settled it was extracting the wiphy's own channel list:

```
Mode[A] Channels: 36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128
                  132 136 140 144 149 153 157 161 165 169 173
```

Channels **169 and 173 were never visited** in the full-scan trace although
they were in the request. Testing an explicit list against the unrestricted
scan:

| scan | crashes |
|---|---|
| 36 explicit channels, ascending | 0 |
| 36 explicit channels, in the kernel's own non-DFS-first order | 0 |
| UNII-2e only (5500-5720, every channel DFS) | 0 |
| UNII-3 only (5745-5825) | 0 |
| the same 36 **+ 5845 + 5865** | 1 |
| **5845 + 5865 alone** | 1 |
| unrestricted full scan (positive control, x5) | 1 each |

Then one channel at a time:

| channel | freq | crashes |
|---|---|---|
| 165 | 5825 | 0, 0 |
| **169** | **5845** | **1, 1** |
| 173 | 5865 | 0, 0 |

Channel 173 is genuinely functional -- requested explicitly it is visited and
returns results (`VISITED: 5825 5865`, 0 crashes) -- so the tail of the 5 GHz
list cannot simply be trimmed. Only 5845 MHz is poison.

## 3. Hypotheses tested and rejected -- do not re-run

- **Radar/DFS handling.** Lance raised this, and the data rules it out from
  both directions. 5845 MHz is UNII-3, not a radar band; DFS is UNII-2A
  (5250-5350) and UNII-2C/2e (5470-5725). The device agrees -- it tags only
  the real ones, `52 = 5260 MHz (NO_IR) (DFS)` -- and 169/173 carry no DFS or
  NO_IR flag. Empirically the DFS channels are the well-behaved ones: a
  UNII-2e-only scan, every channel of it DFS, crashes zero times, as does a
  36-channel scan containing all DFS channels. The one lethal channel is the
  non-DFS one.
- **`WMI_SCAN_FILTER_PROBE_REQ` flag inversion** in `wmi-tlv.c`. Removing it
  still gives exactly one crash per scan. Reverted.
- **Channel count / scan-request size.** 36 explicit channels do not crash;
  the same scan unrestricted does.
- **Channel ordering.** The same 36 in the exact order the full scan uses
  (non-DFS first, DFS last, ending on 5720) does not crash.
- **A specific band boundary.** Neither UNII-2e nor UNII-3 alone crashes.

## 4. The fix

`c44c2e3bf wifi: ath10k: withhold 5845 MHz from the WCN3990 channel list`

A `hw_params` field names a 5 GHz centre frequency the firmware must not be
asked to scan, applied from `ath10k_mac_update_channel_list()` beside the
existing `low_5ghz_chan`/`high_5ghz_chan` clamp. checkpatch --strict 0/0/0.

### Why the firmware cannot gate this itself

Measured on `FWRANGE-20260815T042707Z` with `ath10k_core.debug_mask=0x2`, the
service ready event reports:

```
low_2ghz_chan 2312 high_2ghz_chan 2732 low_5ghz_chan 4912 high_5ghz_chan 6100
```

That is the raw tuning range, not a list of channels the firmware can
service. Every channel in ath10k's 5 GHz table (5180-5865) falls inside
4912-6100, so the existing `low_5ghz_chan`/`high_5ghz_chan` clamp excludes
nothing on this device. **The firmware advertises 5845 MHz and then faults on
it**, which is why a data-driven fix is not available and the frequency has
to be named explicitly.

This also settles the scope question. A firmware that declares a range it
cannot honour is a firmware-family trait rather than a board one, so keying
the field on the WCN3990 `hw_params` entry -- shared with SDM845 and QCS404 --
is the defensible default, with the caveat stated in the commit so a
maintainer with access to those boards can narrow it. Decision by Lance,
2026-08-14.

An aside worth recording: `ieee80211-freq-limit` looks like a zero-driver-
change alternative, since `ath10k_mac_register()` already calls
`wiphy_read_of_freq_limits()`. It is very likely inert here. `net/wireless/of.c`
applies the limit by setting `IEEE80211_CHAN_DISABLED` directly, and that call
sits *before* `ieee80211_register_hw()` -- exactly the position wiped by the
`SET_BY_DRIVER` + `REGULATORY_STRICT_REG` reset described below. Not tested,
but it would fall into the same trap.

### The first attempt was wrong, and why

I first disabled the channel once in `ath10k_mac_register()`, before
`ieee80211_register_hw()`, reasoning that `wiphy_register()` captures
`orig_flags = flags` (`net/wireless/core.c:1037`) and that regulatory updates
rebuild `chan->flags` from `orig_flags` (`net/wireless/reg.c:2571`), so the
bit would survive.

It booted and **changed nothing** -- channel 169 was still listed and still
crashed on all three full scans. The reasoning was right in general and wrong
for this driver. `net/wireless/reg.c:1759`:

```c
	if (lr->initiator == NL80211_REGDOM_SET_BY_DRIVER &&
	    request_wiphy == wiphy &&
	    request_wiphy->regulatory_flags & REGULATORY_STRICT_REG) {
		chan->flags = chan->orig_flags =
			map_regdom_flags(reg_rule->flags) | bw_flags;
```

ath10k goes through `ath_regd_init()`, which sets `REGULATORY_STRICT_REG` and
hints as `SET_BY_DRIVER`, so this branch overwrites **both** `flags` and
`orig_flags` and erases the bit. The correct hook is the regulatory notifier,
which is where ath10k already re-applies its firmware channel limits after
every update.

Worth recording as a general point: a channel flag set before registration is
not durable for a driver that requests its own regulatory domain.

### Does this cost anyone a usable channel?

Not on joan. Channel 169 has never once worked on this hardware: across every
observation, requesting 5845 MHz produced a firmware fault and never a channel
visit, and the full-scan trace shows the firmware silently skipping it. A
channel whose firmware faults when touched cannot carry an association either,
so before the fix an AP on 169 meant a modem crash during the scan that found
it. The fix trades a crash for a clean absence; it does not remove a working
capability.

The channel is also not one access points sit on. Consumer APs use 36-48,
52-64, 100-144 and 149-165; 5845 MHz is above UNII-3's usable top
(165 = 5825 MHz), in the 5.9 GHz band that only became unlicensed in 2020,
which a 2017 Wi-Fi 5 part has no business using and demonstrably cannot tune.

### Why the channel is in the table at all

Not because it is a stray entry. `ath10k_5ghz_channels` is a single static
table shared by **all sixteen** ath10k hardware entries -- qca988x, qca9887,
four qca6174 variants, qca99x0, qca9984/9994, qca9888, qca9377, qca4019 and
wcn3990 -- so it is the union of what any chip of that generation can tune,
not what this one can.

It is also deliberate rather than legacy, and the primary sources say why.
The local clone is shallow, so these were recovered through the GitHub blame
API rather than `git log`:

- **Channel 169** -- commit `34c30b0a5e97` ("ath10k: enable advertising
  support for channel 169, 5Ghz"), 2016-12-30, Mohammed Shafi Shajakhan
  (`mohammed@qti.qualcomm.com`), applied by Kalle Valo:

  > Enable advertising support for channel 169, 5Ghz **so that based on the
  > regulatory domain(country code) this channel shall be active for use**.
  > For example in countries like India this channel shall be available for
  > use with latest regulatory updates

- **Channel 173** -- commit `38441fb6fcbb` ("ath10k: support use of channel
  173"), 2018-06-14, Ben Greear:

  > The India regulatory domain allows CH 173, so add that to the available
  > channel list. **I verified basic connectivity between a 9880 and 9984
  > NIC.**

So both channels exist for **India's regulatory allocation**, and the design
intent was explicitly that *the regulatory domain would gate them*. Note also
that channel 173 was verified on QCA9880 and QCA9984 -- not on WCN3990.
Nobody ever tested 169 on this chip.

**This corrects an earlier reading of mine.** I first explained the entry via
ath12k's `#define ATH12K_5_9_GHZ_MIN_FREQ 5845`, concluding that channel 169
is "the first channel of the 5.9 GHz band". That is how *ath12k* models it,
but it is not why the channel is in *ath10k*: the ath10k rationale is India,
two years before the 5.9 GHz allocation existed. The conclusion is unchanged;
the provenance is not what I said it was.

So the channel was reachable because three layers that could each have
filtered it all default permissive: the driver table is a cross-chip union,
the board's regdomain code is blank so ath substitutes US -- defeating
exactly the gate `34c30b0a5e97` was relying on -- and the firmware declares
its raw 4912-6100 MHz tuning range.

### Upstream precedent for the mechanism

ath12k solves this same class of problem in
`ath12k_mac_update_5_9_ghz_ch_list()`:

```c
	if (test_bit(WMI_TLV_SERVICE_5_9GHZ_SUPPORT, ar->ab->wmi_ab.svc_map))
		return;
	...
	band->channels[i].flags |= IEEE80211_CHAN_DISABLED;
```

That is the same mechanism as this fix -- walk the band, set
`IEEE80211_CHAN_DISABLED` over a frequency range -- but gated on a **firmware
service bit**, so it is discovered rather than hardcoded. ath10k's WMI has no
equivalent bit (`grep` for `5_9`/`SERVICE_5` in `wmi.h`/`wmi-tlv.h` returns
nothing, and ath11k has none either), which is why the frequency has to be
named in `hw_params` here.

## 5. Verification

Boot `CHAN169V2-20260815T033651Z`, image sha256
`bb7362e981cc3686648557c169732abce55ba969e0347a3a7c71fba8bb0630cf`.

Advertised list, 169 gone and 173 kept:

```
Mode[A] Channels: 36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128
                  132 136 140 144 149 153 157 161 165 173
```

**22 consecutive full scans: 0 modem crashes, 0 fatal errors.** Before the
fix the rate was one crash per full scan, 100% reproducible over five
controls. Scans still return 51-69 BSSes. `remoteproc0` stayed `running`
throughout, and GPU runtime PM is unaffected: `runtime_status=suspended`,
`runtime_suspended_time=608469`, 0 SError / panic / internal error.

## 6. Lance's two questions, answered

**Does the crash cost significant power?** I could not measure it, and I am
not going to invent a number. The mainline `pmi8998_fg` `current_now` channel
reports only two values on this device, `0` and `976`, and the readings were
indistinguishable between an idle baseline (`0 976 976 0 0 0 976 0`) and a
three-crash scan loop (`976 0 0 0 976 976`). The phone is also USB-powered
for the debug link, so there is no discharge current to read. What can be
measured is the work per crash: **1.36 s** of modem downtime (crash 195.72 s
-> up 197.08 s), each one a full MBA + MPSS authenticate-and-reload, almost
exactly the cost of the initial cold boot of the modem (1.29 s). Cellular is
dead for that window every time.

**Does it affect an established connection?** Yes, it would have. The WLAN
firmware runs behind MPSS, so a modem crash destroys the association, keys
and session state, not just the interface -- msm8998-mainline #27, a
different fault reached the same way, shows a modem crash taking a
connection down and ending in
`deauthenticated (Reason: 15=4WAY_HANDSHAKE_TIMEOUT)`. A recovered
interface is not a preserved connection. Since a full scan is exactly what a
connection manager does periodically, this was on a timer. With the fix that
trigger is gone.

## 7. Is this an unset country code? No -- the default *is* US

Lance asked whether the crashing channel is exposed because no country code
is set. Measured on `REGTEST-20260815T035411Z` (pre-fix image, so 169 is
live). The driver logs its own answer:

```
ath: EEPROM regdomain: 0x0
ath: EEPROM indicates default country code should be used
ath: country maps to regdmn code: 0x3a
ath: Country alpha2 being used: US
ath: Regpair used: 0x3a
```

The WCN3990's regdomain code is **0x0**, i.e. blank. `__ath_regd_init()`
treats a blank code as "use the default country" and substitutes
`CTRY_UNITED_STATES` outright. So joan is not sitting in a permissive
world/00 fallback -- it comes up as **US**, and US permits 5845 MHz here.

Country hints do work on this device, and do change the outcome:

| country | Mode[A] channels | full scan |
|---|---|---|
| default (US, from blank EEPROM) | ...161 165 **169** 173 | **1 crash** |
| `set country US` explicitly | unchanged, 169 still present | **1 crash** |
| `set country JP` | ...140 144 (all UNII-3 gone) | **0 crashes** |
| back to US (positive control) | 169 present again | **1 crash**, and 5845 alone **1 crash** |

`/lib/firmware/regulatory.db` is present and its certificates load at boot
(`Loaded X.509 cert 'sforshee: ...'`), so the regulatory database is not the
missing piece -- JP demonstrably restricts the list.

### This is not a joan quirk -- SDM845 does the same

sdm845-mainline issue #70, "EEPROM access problems leading to random MAC
address and missing wifi channels" (opened 2026-01-14, still open), shows an
SDM845 device producing output byte-for-byte identical to joan's:

```
ath10k_snoc 18800000.wifi: invalid MAC address; choosing random
ath: EEPROM regdomain: 0x0
ath: EEPROM indicates default country code should be used
ath: country maps to regdmn code: 0x3a
ath: Country alpha2 being used: US
ath: Regpair used: 0x3a
```

So the blank regdomain that lands every WCN3990 mainline port on US, with
channel 169 advertised, is a property of these ports generally rather than
of this board. Devices such as the Ayn Odin (Snapdragon 845, WCN3990,
`ath10k_snoc`, pmaports MR !4986) are in exactly the same position: they
advertise the same channel from the same blank regdomain.

What differs is the firmware. On SDM845 the WLAN firmware is a per-device
`wlanmdsp.mbn` from the vendor image, a different build from joan's
LG-MPSS-embedded 1.0.0.695, and nobody has tested 5845 MHz on those builds.
This cuts both ways for the WCN3990-wide scope: it either protects those
devices from the same latent fault, or costs them an India-only channel they
were unlikely to be using. It does make the shared exposure condition
concrete, which is the part that was previously assumption.

The conclusion is that the regulatory domain is a real lever but the wrong
one to rely on: a country that forbids 5845 MHz masks the crash, and the
device's own default does not. Every joan gets US out of the box and
therefore gets the crash. That is why the fix belongs in the driver rather
than in configuration. Note also that ath10k sets `REGULATORY_STRICT_REG |
REGULATORY_CUSTOM_REG` and applies its custom domain before wiphy
registration, so those disables live in `orig_flags`: a user country hint
can further restrict the list but cannot re-enable what the driver withheld,
which is what makes the fix in section 4 durable against any country setting.

## 8. Open, unrelated: an upstream DT oddity found on the way

`msm8998.dtsi` gives the WCN3990 twelve CE interrupts, but the list starts one
SPI lower than sdm845's and has a hole:

```
msm8998: 413 414 415 416 417 418 [419 missing] 420 421 422 423 424 425
sdm845:  414 415 416 417 418 419 420 421 422 423 424 425
```

`ath10k_snoc_resource_init()` maps these positionally (`snoc.c:1336`,
`platform_get_irq(dev, i)` for `i < CE_COUNT`, 12 on WCN3990), so DT index *i*
is CE *i* and the hole shifts CE6..CE11. The device confirms the hole is live
(`WLAN_CE_6` on hwirq 452 = SPI 420, no 451). Nothing else in `msm8998.dtsi`
claims SPI 419, and the list is upstream torvalds/linux, not something this
port introduced.

**Not the crash**, and not fixed here. `ath10k_snoc_napi_poll()` services every
copy engine on any CE interrupt, so a shifted line is largely masked, and
`/proc/interrupts` shows `Err: 0` with CE4..CE11 all at zero counts. Recorded
because it is a genuine upstream discrepancy worth resolving separately, by
someone who can determine whether the true CE base is 413 or 414.

## 9. State

| lane | state |
|---|---|
| GPU suspend | **PASS**, closed |
| Wi-Fi scanning | **PASS** -- crash root-caused and fixed, 22 clean full scans |
| Bluetooth | controller up, passive LE discovery works; quirks joan-verified only |
| Cellular | MSS + read-only rmtfs + full QMI table **PASS** for scope |
| Sound | blocked: `adsp_mem` 3 MiB short, then no board topology |
| Camera | blocked: no CCI/CSIPHY/sensor DT |

Association is still untested and remains outside the agreed boundary.

## 10. Appendix: WLAN thermal throttling is not available on this firmware

Checked at Lance's request, motivated by Wi-Fi tethering: sustained AP-mode
transmit is the case where throttling would matter. Measured on
`THERMCHK-20260815T052033Z`.

**Result: joan's WCN3990 firmware does not advertise
`WMI_TLV_SERVICE_THERM_THROT`, so no throttling is possible.**

```
cooling_device0 = devfreq-5000000.gpu     <- the only one; no ath10k_thermal
hwmon: ...thermal zones..., pmi8998_charger, qcom_battery   <- no ath10k hwmon
wlan-thermal temp=36100                   <- sensor itself works, 36.1 C idle
```

This is a genuine early return, not a path that never ran:
`ath10k_thermal_register()` is `core.c:3540`, immediately after
`ath10k_mac_register()` at 3516 on the same registration path, and both `phy0`
and `wlan0` exist, so line 3540 was reached. It returned at

```c
	if (!test_bit(WMI_SERVICE_THERM_THROT, ar->wmi.svc_map))
		return 0;
```

### Why there is nothing to implement

The plumbing is already complete for this firmware type -- `wmi-tlv.c:3630`
implements `ath10k_wmi_tlv_op_gen_pdev_set_quiet_mode()`, `wmi-tlv.c:4593`
wires it into `wmi_tlv_ops`, and `wmi-tlv.h:1628` maps
`WMI_TLV_SERVICE_THERM_THROT` to the generic bit. Throttling would work today
if the firmware advertised it. It does not, and commit
`53884577fbcef` ("ath10k: skip sending quiet mode cmd for WCN3990", Rakesh
Pillai, 2018) exists precisely because sending the command to firmware that
lacks it raises a fatal exception,
`err_qdi.c:456:EX:wlan_process:1:WLAN RT:207a:PC=b001b4f0` -- the same fault
class as the channel 169 crash, and the same shape of fix: stop the host
sending what the firmware cannot handle.

### What would remain possible

Even with the service bit, automatic in-kernel throttling via the DT zone
would need two further changes, so it was never a config tweak:

1. `msm8998.dtsi`'s `wlan-thermal` has a single trip of type `"hot"`, which is
   notification-only, and no `cooling-maps`. It would need a `passive` trip
   plus a map.
2. ath10k registers its cooling device with
   `thermal_cooling_device_register()` (`thermal.c:164`), which has no backing
   `device_node`, so DT `cooling-maps` cannot reference it by phandle -- unlike
   msm8998's GPU zones, the file's only two maps, which bind
   `<&adreno_gpu 0 6>`. Binding it would require ath10k to switch to
   `devm_thermal_of_cooling_device_register()` with `#cooling-cells`, an
   upstream change affecting every ath10k platform.

For tethering the practical mitigation is therefore host-side: the
`wlan-thermal` zone reads correctly, so userspace can watch it and reduce TX
power, narrow the channel, or stop the AP. No kernel change needed for that.

**Bigger unknown first:** AP mode on joan is completely untested. ath10k
advertises `NL80211_IFTYPE_AP`, but nothing has exercised it, and issues
#26/#27 are on the *station* association path (hostapd runs the authenticator
side in AP mode), so whether they apply is unknown. Establishing that AP mode
works at all should precede any thermal work.

## 11. Appendix: calibration and board_id are already correct

Investigated under the goal "fix LG V30 mainline wifi calibration and
board_id", after AP-mode throughput came in low and `board_id 0xff` plus
`invalid MAC address; choosing random` looked like a calibration failure.

**They are not broken. The suspicion was wrong, and the evidence says so.**

### Calibration data is the correct file

```
/lib/firmware/ath10k/WCN3990/hw1.0/board.bin
md5 8c5e6060d42f9bc4b28e686081a6df0b
```

That is byte-identical to LG's own `bdwlan.bin`. It is also the *only* board
file present -- there is no `board-2.bin`.

### `board_id 0xff` is provably inert here

`qmi.c:619` shows `0xFF` is simply the fallback when the QMI response carries
no `board_info`. Every use of the value is then:

```
core.h:1097   u32 qmi_board_id;
qmi.c:869     ar->id.qmi_board_id = qmi->board_info.board_id;
core.c:1587   scnprintf(... "bus=%s,qmi-board-id=%x,qmi-chip-id=%x%s" ...)
core.c:1593   scnprintf(... "bus=%s,qmi-board-id=%x" ...)
```

Both remaining uses are inside `ath10k_core_create_board_name()`, which builds
the lookup key for **board-2.bin**. And `ath10k_core_fetch_board_file()`
(`core.c:1668`) only uses that key for the api-2 path:

```c
	ar->bd_api = 2;
	ret = ath10k_core_fetch_board_data_api_n(ar, boardname, ...);
	if (!ret) goto success;
fallback:
	ar->bd_api = 1;
	ret = ath10k_core_fetch_board_data_api_1(ar, bd_ie_type);
```

With no `board-2.bin`, the api-2 lookup fails, ath10k falls back to
`bd_api = 1`, and `board.bin` is loaded by fixed path -- no name, no board id
consulted. The boot log confirms that path ran: `board_file api 1`.

`qcom,calibration-variant` would likewise change nothing, since a variant only
selects *within* board-2.bin. joan's DT lacking it (where
`msm8998-lenovo-miix-630.dts` has it) is therefore not a defect.

### The random MAC is real, but is not a calibration fault

`core.c:3453` fetches the MAC with `device_get_mac_address(ar->dev, ...)`,
i.e. from DT `mac-address` / `local-mac-address` / nvmem only. joan's wifi
node has none, the firmware's WMI ready event supplies nothing
(`wmi.c:5769` leaves it zero), so `mac.c:10014` falls back to
`eth_random_addr()` -- hence the `52:` locally-administered address.

The MAC is **not** in the persist partition: mounted read-only, it contains
only `rfs/msm/mpss/server_check.txt`, `rfs/shared/server_info.txt`,
`sensors/sensors_settings` and `.twrps`. It therefore lives in modem NV,
reachable only over QMI, which is why nothing on the Linux side finds it.

A random MAC does not affect throughput. Supplying the real one is a
correctness fix, and a per-device value cannot go into a shared DTS, so an
upstreamable fix needs nvmem or a QMI path rather than a hardcoded property.

**Conclusion: the AP throughput ceiling is not a calibration or board-id
problem, and neither needs fixing.** The remaining suspect is the AP transmit
path itself.

## 12. Appendix: tethering works, and what it actually pushes

AP mode was brought up on joan and measured under the goal "confirm tethering
can push the true limits". Run `APMODE-20260815T052619Z`.

### It works

`hostapd` v2.12 (fetched into tmpfs, not installed) driving `wlan0` as an AP
on channel 36 at **80 MHz**, WPA2, with `dnsmasq` for DHCP. A Galaxy Z Fold 5
associated, took a lease, and reached the internet through joan; NAT was done
on nym-nest because joan's kernel has no `NF_TABLES` (see below).

### Throughput, measured

The pure Wi-Fi hop, AP -> client, fetching a 60 MiB file over HTTP:

| client | link | AP -> client |
|---|---|---|
| nym-nest (802.11n, HT40, MCS 4) | 81 Mbit/s PHY | **33.6 Mbps** |
| nym-fang (Pi 4B, VHT80, VHT-NSS 1) | 325 Mbit/s PHY | **63.1 / 67.5 / 65.1 Mbps** |

Three consecutive VHT80 runs agree within 7%. For context on the rest of the
chain: nym-nest to the internet is ~590 Mbps, and joan to the internet over
the USB link (no Wi-Fi hop) is 214-246 Mbps. **The Wi-Fi hop is the limiting
segment, and doubling the channel width roughly doubled it**, which is what a
healthy radio should do. `crashes=0 fatal=0`, modem `running`, across ~190 MB.

The Pi is a single-stream client seen at -73 dBm, so 63-68 Mbps is not joan's
ceiling either. The Fold 5 negotiates VHT-MCS 4 / 80 MHz / **NSS 2** at
390 Mbit/s, i.e. twice the spatial streams and a stronger signal.

### A retraction

Earlier in this investigation I computed an "effective AP TX rate" of roughly
5 Mbps by dividing `tx bytes` by `tx duration` from the station dump, and used
it to argue joan's transmitter was crippled. **That was wrong.** The station
dump reports `tx duration: 286321855 us` -- 286 seconds of airtime -- for
about 23 seconds of transfers. The counter is not populated meaningfully by
this firmware, the same way the PDEV TX stats are all zero. Measured
throughput of 63-68 Mbps contradicts the inference, and the measurement wins.

A related near-miss worth recording: a client-side `rx bitrate: 6.0 MBit/s`
reading looked like rate control pinned to the basic rate, but with no bulk
data in flight it was only beacons and management frames. Rates from a station
dump mean nothing unless traffic is actually flowing.

### Two real bugs found along the way

1. **`failed to install key ... -110` occurs in AP mode.** This is the
   signature from msm8998-mainline #26/#27, previously only reported for a
   station associating outward. In AP mode it makes the 4-way handshake fail,
   which both Android and `wpa_supplicant` report as a wrong password
   (`4-Way Handshake failed - pre-shared key may be incorrect`). It is
   intermittent, leaves the peer wedged (`failed to disassociate station:
   -95`), and is cleared by restarting hostapd. It does **not** crash the
   modem. This corrects an earlier claim of mine that those bugs do not affect
   the AP path.

2. **The kernel config cannot NAT.** `CONFIG_NF_TABLES` is absent and
   `CONFIG_IP_NF_IPTABLES=m` -- a module, and a RAM boot cannot load modules.
   NetworkManager's `ipv4.method shared` therefore silently installs no
   masquerade rule, and hotspot NAT is impossible on this build. Real tethering
   on joan needs `NF_TABLES`, `NF_NAT` and `NFT_MASQ` built in as `=y`.

### Host-side notes

- `hostapd`, `iw` and `wpa_supplicant` were run from tmpfs on the respective
  machines; nothing was installed on joan or nym-nest. A pacman attempt on
  nym-nest failed on a stale package database and rolled back cleanly.
- nym-nest's Wi-Fi is 802.11n only (zero VHT capability), so it cannot test
  VHT80 at all.
- nym-fang's radio was soft-blocked by rfkill, which made `iw scan` return
  zero APs -- indistinguishable from being out of range until the scan was
  positive-controlled. `rfkill unblock wifi` fixed it; its regulatory domain
  was already US.
