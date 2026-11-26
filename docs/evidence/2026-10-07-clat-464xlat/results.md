# CLAT / 464XLAT on joan — results (2026-10-07)

Fulgor (ZCode:GLM-5.3) found the NM-native dead end and got clatd translating
on the bench (spec.md here); Ember (Claude-Code:claude-opus-5-5) packaged it and
made it hold up across reconnects. Bench: US998, linux-lg-joan r57 (ee468f34),
T-Mobile US SIM (IPv6-only bearer), NetworkManager 1.58.0, systemd-resolved 262.

## What ships

pmaports `lg-joan-cellular-data` 0.2-r6 (commit c0d77b7540):

| file | role |
|---|---|
| depends `clatd` (Alpine edge/testing, Tore Anderson, MIT) | RFC 7050 DNS64 discovery + TAYGA translator; its `50-clatd` NM dispatcher hook restarts `clatd.service` on every connection up/down |
| `clatd.service` | from clatd's own unit; not enabled at boot, dispatcher-driven |
| `clatd.conf` | keeps clatd's native-IPv4 check (dual-stack / IPv4 Wi-Fi untouched), grace 10s -> 2s |
| `joan-clat-run` | ExecStart: discovery against the current link's own DNS servers (`dns64-servers=`) |
| `joan-clat-reset` | ExecStartPre: clear state a killed clatd leaves |
| `joan-clat-up` / `-down` | source rule into the modem route table + forward-chain accepts |
| `40-joan-rmnet-nodad` | NM dispatcher: rescue a dadfailed/tentative modem address |

## Why each piece exists

1. **NM 1.58 native CLAT is useless on cellular**: it learns the NAT64 prefix only
   from RA PREF64; 3GPP bearers send no RAs (NM-ci `clat.feature` covers
   ethernet/vlan/ip6gre only). `ipv4.clat` left at default.
2. **pmOS routing**: `postmarketos-base-ui-networkmanager`'s
   `50-wwan-policy.conf` puts gsm routes in table 1430 behind
   `oif <modem dev>`; packets tayga writes back into the tun have no oif yet and
   miss it. **pmOS firewall**: `inet filter forward` is policy drop; tun->modem
   is forwarding. Both affect any pmOS phone on an IPv6-only SIM (upstream
   candidate).
3. **Discovery through resolved fails intermittently** and clatd's discovery is
   one-shot (exit 0, no retry):
   - before NM pushes link servers, resolved answers from fallback (Quad9),
     no DNS64;
   - DNSSEC=allow-downgrade: resolved queries a new server with DO+CD; a DNS64
     server answers that unsynthesised (RFC 6147 5.5). Measured with Net::DNS:
     `fd00:976a::9` DO=1 CD=1 -> NOERROR, empty answer; `fd00:976a::10`
     synthesises regardless.
   - Through resolved: v4 back in only 1/6 cycles (r4). Querying link servers
     directly (r5+): 8/8.
   - The two T-Mobile servers use different prefixes: `::9` ->
     `2607:7700:0:13:0:2::/96` (NSP), `::10` -> `64:ff9b::/96` (WKP). Both
     route (ping 8.8.8.8 via each).
4. **DAD race**: every reconnect creates a new `qmapmux2.0`; NM adds the carrier
   address before `70-joan-rmnet-nodad.rules` sets `accept_dad=0`, so it
   sometimes ends `dadfailed tentative` ("duplicate address ... used by
   3a:ff:fe:80:00:00") and IPv6 is dead until the next reconnect. Seen live at
   09:20 after one `nmcli con up`. Race-free fix is kernel-side: linux branch
   `joan/rmnet-noarp` 6e8de9d415e3 sets `IFF_NOARP` in `rmnet_vnd_setup()`.

## Bench results (lg-joan-cellular-data 0.2-r5/r6)

| scenario | runs | IPv6 back | IPv4 back | notes |
|---|---|---|---|---|
| `nmcli con down/up` | 8/8 (r5) + 2/2 (r6) | 3-5 s | 15-16 s (r5), 7 s (r6) | rules exactly once; DAD rescue fired in several |
| Wi-Fi up (dual-stack home LAN) | 3/3 | native | native via wlan0 | clatd exits, no clat dev |
| Wi-Fi down | 3/3 | yes | ~12 s via CLAT | |
| `nmcli radio wwan off/on` | 2/2 | 8 s | 8 s | |
| modem remoteproc stop/start | 1/1 | 26 s | 26 s | carrier gave a NEW /64 (2607:fb91:...), DAD rescue fired |

Not yet covered: reboot, a second SIM/carrier (dual-stack, IPv4-only), roaming,
hotspot clients over CLAT, v6-only Wi-Fi without DNS64 while cellular has NAT64
(clatd would pick the Wi-Fi side and give no IPv4; documented limitation).

## Kernel fix, tested live without a reboot (10:08-10:15)

`rmnet` is a module (`CONFIG_RMNET=m`), so the patched `rmnet.ko`
(`joan/rmnet-noarp` 2cdfec0ab5a9) was built in the pmbootstrap chroot with the
r57 toolchain (Alpine gcc 15.2.0) and the r57 config, then swapped into the
running kernel with cellular down. Pitfall on the way: without `pahole` in the
chroot, Kconfig silently drops `CONFIG_DEBUG_INFO_BTF`, which changes
`struct module` ("this_module section size must match"); compare
`readelf -S` `.gnu.linkonce.this_module` sizes (0x500 here) before loading.

- A hand-made `rmnet` link comes up `<NOARP>` with `accept_dad=-1`.
- ModemManager's link loses `NOARP` again: libqmi's RTM_NEWLINK carries
  `ifi_flags=0, ifi_change=0xFFFFFFFF`, applied by `rtnl_configure_link()`
  after `register_netdevice()`. `accept_dad` is already -1 by then, so DAD
  stays off.
- udev rule AND dispatcher hook both disabled: 6/6 reconnects, every new
  `qmapmux3.0` had `accept_dad=-1`, no tentative/dadfailed address, 0
  duplicate-address messages, IPv6 back in 4-5 s, IPv4 in 7-10 s.
- Stock module restored afterwards (bench = r57 + lg-joan-cellular-data 0.2-r6).

## Second modem restart (10:12) and a Wi-Fi casualty

Cellular + CLAT recovered from a second remoteproc restart too. Wi-Fi did not
survive the first one (09:54): ath10k logs `-108` (ESHUTDOWN) on every vdev
create afterwards; WCN3990 firmware runs on the modem and ath10k never
re-initialised. A module reload then failed for good:

- `ath10k_qmi_deinit()` (rmmod) does not undo the MSA permission assignment;
  only the server-exit path does. Reload with firmware up -> "msa info req
  rejected: 90" (firmware already has MSA); reload after another modem restart
  with the driver unloaded -> "failed to assign msa map permissions: -22"
  (memory still owned by the remote VMs).
- Bench Wi-Fi stays down until a reboot. Kernel candidates: re-init ath10k on
  FW_READY after modem SSR; release MSA permissions in `ath10k_qmi_deinit()`.
