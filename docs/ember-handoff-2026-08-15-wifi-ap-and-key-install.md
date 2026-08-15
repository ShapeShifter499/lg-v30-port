# Wi-Fi handoff, 2026-08-15: crash fixed; no teardown-key SEC_IND observed for `-110`

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-15

Follow-up-by: Hermes Agent:moa/deep-flash
Follow-up-date: 2026-08-15

For whoever picks this up next -- a future me, or Aurel. Supersedes the open
Wi-Fi items in `ember-handoff-2026-08-14-gpu-closed-connectivity-state.md`.
Full detail lives in `ember-wifi-modem-crash-rootcaused-2026-08-14.md`; this
is the short version plus what to do next.

## 1. What is done

| lane | state |
|---|---|
| GPU runtime suspend | **PASS**, closed earlier |
| Wi-Fi scanning | **FIXED** -- the per-scan modem crash is gone |
| Wi-Fi AP mode / tethering | **WORKS**, measured, with one caveat below |
| Cellular | PASS for scope (no registration attempted) |
| Bluetooth | controller up, quirks joan-verified only |
| Sound / camera | still blocked, untouched this session |

### The headline fix

Scanning **channel 169 (5845 MHz)** made the WCN3990 firmware take a fatal
exception, `err_qdi.c:450 ... PC=b01c4d3c`, which took the modem down with it.
One crash per full scan, 100% reproducible across five positive controls.
Withholding that one channel gives **22 consecutive clean full scans**.

`wifi: ath10k: withhold 5845 MHz from the WCN3990 channel list`

Keyed on the WCN3990 `hw_params` entry, so it also covers SDM845/QCS404. That
scope was Lance's explicit decision after the trade-off was laid out, and the
caveat is stated in the commit body.

### What was disproved, so nobody repeats it

- **Calibration and `board_id` are not broken.** `board.bin` md5
  `8c5e6060d42f9bc4b28e686081a6df0b` is byte-identical to LG's `bdwlan.bin`,
  and `qmi_board_id`'s only consumers build the board-2.bin lookup key. With
  no board-2.bin, `ath10k_core_fetch_board_file()` falls back to `bd_api = 1`
  and loads `board.bin` by fixed path. `board_file api 1` in the log confirms
  it. `qcom,calibration-variant` would be inert for the same reason.
- **The crash is not msm8998-mainline #26/#27.** Those are `PC=b00bfa9c` on
  firmware 1.0.0.483 triggered by connect/disconnect; ours was `PC=b01c4d3c`
  on 1.0.0.695 triggered by a scan. They share `err_qdi.c:450` only because
  that is the firmware's generic exception reporter.
- **Not DFS/radar, not channel count, not channel ordering, not a band
  boundary, not the `WMI_SCAN_FILTER_PROBE_REQ` inversion.** All tested.

## 2. Where the code is

Kernel, `~/vibe-coding-projects/coding/linux-mainline-v30-a540-hwinit-gate`,
branch `joan/a540-suspend-hwinit-gate`, HEAD `519646f01`.

Pushed to `ghfork` = `github.com/ShapeShifter499/linux-lg-v30-joan`:

- `joan/latest-clean-test` -> `5fbb6db35` (everything)
- `master` -> `b4f2ab727` (verified fixes only)

**`origin` in that repo is torvalds/linux. Never push there.**

Docs repo `~/vibe-coding-projects/coding/lg-v30-port`, branch
`aurel/card94-reset-script`; the pre-diagnostic handoff commit was `d1b86a4`.

## 3. `-110` classified: the association key succeeded; teardown-key deletion lost its indication

**This section supersedes the earlier association-time diagnosis. Do not run
another association merely to repeat this split.** The one-variable HTT-debug
boot and one controlled nym-fang association were completed and the evidence
was sealed before recovery.

### Exact diagnostic

- Intended/current source baseline: kernel `519646f01`; source AP image SHA-256
  `bb7362e981cc3686648557c169732abce55ba969e0347a3a7c71fba8bb0630cf`.
  The runtime release was `7.2.0-rc2-gd05e70c5e484-dirty`, so exact build-source
  provenance is inherited from that source image and remains unproven.
- Only changed variable: kernel command line gained
  `ath10k_core.debug_mask=0x8`; runtime sysfs value was exactly `8`.
- RAM-only candidate SHA-256:
  `3dfad94194d3bedef972eed11c7c9a37aa1cee3427042682605b03479171b19f`.
- AP: BSSID `be:a7:df:92:bf:78`, channel 36/VHT80. Client:
  `e4:5f:01:07:fc:f3` (nym-fang). Exactly one controlled association.

### What the correlated logs prove

The client mapped to HTT peer ID 30:

```
[731.474514] htt peer map vdev 0 peer e4:5f:01:07:fc:f3 id 30
```

The WPA2 four-way handshake reached hostapd's pairwise `NEW_KEY` at
731.568572. The firmware returned the matching indication about 21 ms later:

```
[731.589262] sec ind peer_id 30 unicast 1 type 6
```

Hostapd then marked the station connected and the pairwise handshake complete;
the client independently logged `WPA: Key negotiation completed` and
`CTRL-EVENT-CONNECTED`. Therefore the association-time PTK installation was
**matched and on time**, not lost or late.

The controlled client process was stopped about 12 seconds later. The client
sent disassociation reason 8 at 743.699674. Hostapd immediately issued a
pairwise `DEL_KEY` at 743.709249. That call blocked for the driver's three-second
completion timeout; the kernel reported at 746.976115:

```
ath10k_snoc 18800000.wifi: failed to install key for vdev 0 peer e4:5f:01:07:fc:f3: -110
```

Despite the generic wording, this occurrence belongs to the **DISABLE_KEY /
pairwise teardown path**, not the successful initial key install. No further
`SEC_IND` appeared through the evidence seal at uptime 936.982. Classification:
**no matching teardown indication observed; lost from the host's perspective**.
It was not late within the captured ~190-second tail, and it was not
mismatched: the only client-unicast indication was the prompt, matching peer-30
indication for the successful install. This does not prove transport loss;
whether firmware generated a delete acknowledgement remains open.

### SMMU lead downgraded for this timeout

There were five WLAN stream-`0x1900`, `iova=0` SMMU faults before the controlled
association, but the count stayed exactly five from pre-association through
the timeout and evidence seal. There were no `failed to extract amsdu`, modem
fatal, or crash events in this run. The faults remain a real independent issue,
but this experiment directly rejects them as the proximate cause of this
specific lost teardown acknowledgement. Deprioritize SMMU work unless a future
timeout coincides with a new fault.

### Mechanism and next steps

`ath10k_install_key()` waits on the same `install_key_done` completion for both
`SET_KEY` and `DISABLE_KEY`; the HTT `SEC_IND` handler is still the only normal
completion source. Next work, in order:

1. Instrument the wait boundary with command (`SET_KEY` versus `DISABLE_KEY`),
   peer, key index/flags, and begin/end timestamps so the generic warning can no
   longer obscure which operation timed out.
2. Compare downstream/CAF WCN3990 behavior and determine whether this firmware
   is expected to emit `SEC_IND` for key deletion.
3. If downstream confirms no delete acknowledgement, test a narrowly scoped
   WCN3990/SNOC change that skips the `SEC_IND` wait only for key disable while
   preserving the wait for real installs. Do not globally raise the timeout.
4. Separately explain why stopping the client triggers this cleanup failure and
   whether the earlier apparent "wrong password" reports were actually a
   different event; this run did not reproduce a failed association.

### Do not bother with

- **`cryptmode=1` (software crypto).** It would bypass hardware key install,
  but `core.c:2675` requires raw-mode firmware support and joan reports `raw 0`.
- **PMF / 802.11w.** Setting `ieee80211w=0` explicitly changed nothing.
- **Two spatial streams.** A confirmed one-chain VHT80 test changed nothing.
- **Progressive state degradation.** NetworkManager worked later in the same
  prior boot.
- **Raising the three-second timeout as the first fix.** No delete indication
  appeared even through the long tail, so this result is lost, not merely late.

The prior NetworkManager-versus-hostapd split is now narrower: compare their
**disconnect/key-delete sequences**, not just association key installation.

## 4. Tethering: what it does

AP mode works. hostapd v2.12 on channel 36 at **80 MHz** with WPA2, dnsmasq
for DHCP, a phone associated and reached the internet through joan.

| client | link | AP -> client |
|---|---|---|
| nym-nest (802.11n, HT40) | 81 Mbit/s PHY | **33.6 Mbps** |
| nym-fang (Pi 4B, VHT80, NSS 1) | 325 Mbit/s PHY | **63.1 / 67.5 / 65.1 Mbps** |
| Fold 5 via NetworkManager, HT20 | 20 MHz | 10-16 Mbps |

For context: joan reaches the internet over USB at 214-246 Mbps and nym-nest
at ~590 Mbps, so the Wi-Fi hop is the limiting segment. **Doubling channel
width roughly doubled throughput**, which is what a healthy radio does.
`crashes=0` across ~190 MB.

**A retraction to be aware of:** an earlier "~5 Mbps effective AP TX",
computed as `tx bytes / tx duration` from the station dump, was wrong. That
counter reports 286 s of airtime for ~23 s of transfers -- it is not populated
meaningfully by this firmware, like the all-zero PDEV TX stats. Do not trust
either. Related trap: a station dump's `rx bitrate` means nothing unless bulk
traffic is actually flowing; a `6.0 MBit/s` reading was just beacons.

### Kernel config gap for tethering

`CONFIG_NF_TABLES` is absent and `CONFIG_IP_NF_IPTABLES=m` -- a module, and a
RAM boot cannot load modules. So NetworkManager's `ipv4.method shared`
silently installs no masquerade and **hotspot NAT is impossible on this
build**. This session worked around it by doing the NAT on nym-nest. A proper
tethering config needs `NF_TABLES`, `NF_NAT` and `NFT_MASQ` as `=y`.

## 5. Loose ends someone should close

- **The prior runtime host state is now cleaned up.** nym-nest has no remaining
  `10.42.0.0/24` route/forward/NAT rule and its pmOS USB interface is gone;
  nym-fang has no test routes, is NetworkManager-managed again, its system
  wpa_supplicant is running, and Wi-Fi was restored to its original disabled
  state. The older cleanup commands remain below only as historical detail:

```sh
# nym-nest
sudo iptables -D FORWARD -s 10.42.0.0/24 -j ACCEPT
sudo iptables -t nat -D POSTROUTING -s 10.42.0.0/24 -j MASQUERADE
sudo ip route del 10.42.0.0/24 via 172.16.42.1 dev enp0s29u1u5
# nym-fang -- its radio was rfkill-blocked before this session
sudo ip route del 8.8.8.8/32 via 10.42.0.1 dev wlan0
sudo ip route del 172.217.0.0/16 via 10.42.0.1 dev wlan0
sudo pkill -x wpa_supplicant; sudo ip addr del 10.42.0.7/24 dev wlan0
sudo ip link set wlan0 down; sudo rfkill block wifi
```

- **`gh auth setup-git` was run on nym-skyforge** this session so git could
  push over HTTPS; it added a credential helper to the global gitconfig.
- **A stray `=l-45` file** sits untracked in the kernel repo, from a broken
  shell redirect of mine. Lance's call whether to delete it.
- **joan's WLAN MAC is random** (`52:`/`a2:` locally-administered). ath10k
  reads it only from DT via `device_get_mac_address()` (`core.c:3453`), joan's
  wifi node has none, and the persist partition holds no `wlan_mac` file --
  mounted read-only, it contains only `rfs/msm/mpss/server_check.txt`,
  `rfs/shared/server_info.txt`, `sensors/sensors_settings` and `.twrps`. It
  lives in modem NV behind QMI. Does not affect throughput. A per-device value
  cannot go in a shared DTS, so an upstreamable fix needs nvmem or a QMI path.
- **Thermal throttling is unavailable**: the firmware does not advertise
  `WMI_TLV_SERVICE_THERM_THROT`, so no `ath10k_thermal` cooling device exists.
  Not fixable from the host. Details in section 10 of the root-cause doc.
- **An upstream DT oddity, unrelated**: msm8998.dtsi gives WCN3990 twelve CE
  interrupts starting one SPI lower than sdm845 *and* skipping 419
  (`413..418, [419 gone], 420..425`). Mapping is positional, so it shifts
  CE6..CE11. Confirmed live on the device. Not the crash, not fixed, worth
  resolving by someone who can determine whether the true base is 413 or 414.

## 6. Reproduction notes

RAM boots only throughout; no partition was ever flashed. `rmtfs` read-only,
and **use `-r -P -s`** -- the `-s` flag makes rmtfs notice modem restarts and
cut the crash rate roughly threefold.

Helpers on nym-nest in `~/joan-images/staging/`: `stage.sh` (one stage, fetch
immediately), `stage-candidate.sh` (package + verify + stage + hash-bound
runner), the per-image `*-ramboot-once.sh` runners, and
`a540-hwinit-recover-lineage-on-nest.sh <RUN_DIR>` to get back to LineageOS.

The recovery helper has one known false-negative trap: with `set -euo pipefail`,
an expected zero-match `lsusb` probe can terminate its polling loop after the
reboot command. In this diagnostic the helper returned 1, but direct ADB
verification proved LineageOS fully booted and pmOS transport absent. Fix the
probe before relying on the helper's exit status alone.

`hostapd`, `iw` and `wpa_supplicant` were all run **from tmpfs** (`apk fetch`
or an Arch package extracted with `tar -I zstd`), never installed. That
technique works well and is worth reusing.

Two shell traps that cost time here: busybox `ip` has no `-br`, and
`pkill -f "<pattern>"` will match the ssh command line carrying that pattern
and kill your own session -- use `pkill -x <name>`.
