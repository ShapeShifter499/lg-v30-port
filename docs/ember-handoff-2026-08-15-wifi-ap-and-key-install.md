# Ember handoff, 2026-08-15: Wi-Fi crash fixed, tethering measured, `-110` key install open

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-15

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
`aurel/card94-reset-script`, pushed to `ghpub` at `31c3894`.

## 3. The open problem: `-110` on key install

This is the one worth picking up.

### Symptom

In AP mode, associating clients intermittently fail with

```
ath10k_snoc 18800000.wifi: failed to install key for vdev 0 peer <mac>: -110
ath10k_snoc 18800000.wifi: cipher 0 is not supported
ath10k_snoc 18800000.wifi: failed to disassociate station: <mac> vdev 0: -95
```

The client sees it as a **wrong password** -- both Android and
`wpa_supplicant` report the failed 4-way handshake that way
(`4-Way Handshake failed - pre-shared key may be incorrect`). It does **not**
crash the modem.

### Mechanism, established

`-110` is `ETIMEDOUT` from `ath10k_install_key()` (`mac.c:307`):

```c
	reinit_completion(&ar->install_key_done);
	if (arvif->nohwcrypt)
		return 1;
	ret = ath10k_send_key(arvif, key, cmd, macaddr, flags);
	time_left = wait_for_completion_timeout(&ar->install_key_done, 3 * HZ);
	if (time_left == 0)
		return -ETIMEDOUT;
```

`install_key_done` is completed by **exactly one thing**: the firmware's
`HTT_T2H_MSG_TYPE_SEC_IND` message (`htt_rx.c:4181`). The other `complete()`
(`core.c:2587`) is the crash-recovery path unblocking all waiters. So `-110`
means *the firmware did not send an HTT security indication within 3 s*.

### The lead: the WLAN is faulting the IOMMU

```
arm-smmu 16c0000.iommu: Unhandled context fault: fsr=0x402, iova=0x00000000,
                        fsynr=0x1, cbfrsynra=0x1900, cb=1
ath10k_snoc 18800000.wifi: failed to extract amsdu: -11
```

`16c0000.iommu` is `anoc2_smmu` (msm8998.dtsi:1116) and the wifi node declares
`iommus = <&anoc2_smmu 0x1900>, <&anoc2_smmu 0x1901>` (msm8998.dtsi:3866). So
**`cbfrsynra=0x1900` is the WLAN**, doing DMA to **address zero**, repeatedly
(t=2408, 2665, 2670, 3188, 3189, 3331, 3336, 3528 in one boot), interleaved
with corrupted RX (`failed to extract amsdu: -11`).

A device whose DMA is faulting will drop HTT messages. That is exactly the
symptom. It may also explain #26/#27's `unhandled tx completion status 5`,
which is the same family of "HTT came back wrong".

### Next steps, in order

1. **Split "lost" from "late".** Boot with `ath10k_core.debug_mask=0x8`
   (`ATH10K_DBG_HTT`) and hostapd, and watch for `sec ind peer_id ...` during
   a failing handshake. If it never appears, the SMMU lead is the thing. If it
   appears at ~3.5 s, the event is merely late and raising the timeout fixes
   it outright. One boot, and it decides the whole direction.
2. **Chase the `iova=0` fault.** This is *our* bug rather than a firmware one,
   which makes it far more tractable than the upstream position implies.
   Check whether stream `0x1901` is correct/needed, whether the wifi node
   wants `dma-coherent`, and the MSA region handling (`qcom,msa-fixed-perm`
   was reverted, so that path is live). `ath10k_ce_alloc_rri()` uses
   `dma_alloc_coherent(ar->dev, ...)` and is properly mapped, so the RRI ring
   is probably not the source.
3. Only then consider timeout/retry patches. Note Kalle Valo's position on the
   ath10k list is that the proper fix belongs in firmware, and the one
   proposed patch merely shortened the wait.

### Do not bother with

- **`cryptmode=1` (software crypto).** It would bypass hardware key install
  entirely, but `core.c:2675` requires raw-mode firmware support and joan
  reports `raw 0`. Dead end.
- **PMF / 802.11w.** Setting `ieee80211w=0` explicitly changed nothing.
- **Two spatial streams.** Forcing one chain
  (`iw phy phy0 set antenna 1 1`, confirmed `Configured Antennas: TX 0x1 RX
  0x1`) while keeping VHT80 changed nothing.
- **Progressive state degradation over a long boot.** Fitted well -- the
  `-110` errors only start at t~1397 s -- but was rejected when restoring the
  NetworkManager hotspot even later in the same boot worked immediately.

### The unexplained split

The same phone works under **NetworkManager's** wpa_supplicant AP mode on
either band, and fails under **hostapd** on every configuration tried, while a
Pi 4B client works under hostapd at VHT80 for 326 s and 200 MB. That points at
something in the hostapd association/key sequence rather than a client
capability, and it is not isolated. Diffing the two daemons' association and
key-install sequences with `debug_mask=0x8` would likely settle it alongside
step 1 above.

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

- **Host state left up** (all runtime-only, nothing installed anywhere; a
  pacman attempt on nym-nest failed on a stale db and rolled back cleanly):

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

`hostapd`, `iw` and `wpa_supplicant` were all run **from tmpfs** (`apk fetch`
or an Arch package extracted with `tar -I zstd`), never installed. That
technique works well and is worth reusing.

Two shell traps that cost time here: busybox `ip` has no `-br`, and
`pkill -f "<pattern>"` will match the ssh command line carrying that pattern
and kill your own session -- use `pkill -x <name>`.
