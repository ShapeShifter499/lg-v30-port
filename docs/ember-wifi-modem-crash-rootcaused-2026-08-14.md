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
port, and matches upstream msm8998-mainline issue #27.

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

`04a93a807 wifi: ath10k: withhold 5845 MHz from the WCN3990 channel list`

A `hw_params` field names a 5 GHz centre frequency the firmware must not be
asked to scan, applied from `ath10k_mac_update_channel_list()` beside the
existing `low_5ghz_chan`/`high_5ghz_chan` clamp. checkpatch --strict 0/0/0.

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
and session state, not just the interface -- upstream #27 shows the sequence
ending in `deauthenticated (Reason: 15=4WAY_HANDSHAKE_TIMEOUT)`. A recovered
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
