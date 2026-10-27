# CLAT / 464XLAT follow-up spec (banked 2026-10-07, Fulgor ZCode:GLM-5.3)

Goal: any user SIM gets its official IPv4+IPv6 paths where they exist.

## Verified on bench (TMUS SIM, r57, 2026-10-07)
- Carrier connection is IPv6-only (Ipv6OnlyAllowed); IPv4 literals unreachable, hostnames fine.
- RFC 7050 probe: `getent ahosts ipv4only.arpa` -> synthesized AAAA 64:ff9b::c000:aa/ab
  => carrier DNS64 live, well-known prefix 64:ff9b::/96.
- NAT64 data path: ping 64:ff9b::808:808 (8.8.8.8 in WKP) -> 2/2 replies, 37-83 ms.
- Shipped profile is already generic: lg-joan-cellular-data pkg -> empty [gsm] APN
  (provider-DB driven), ipv4.method=auto + ipv6.method=auto => NM requests IPv4v6 bearer.

## Design (carrier-agnostic, no carrier identity anywhere)
NM dispatcher hook on rmnet up: read negotiated bearer family (mmcli bearer ip-type /
v4 route presence). If v6-only: RFC 7050 discovery; if DNS64+NAT64 answers -> start
clatd; else do nothing. Stop on connection down. Dual-stack carriers: no-op.
v4-only carriers: v4 only (no client-side v6 exists) -> README note.

## Work items
1. Package clatd (perl daemon; deps: iptables, tun) in device/testing/ OR minimal
   sh+nft equivalent if perl too heavy.
2. NM dispatcher script + install in same package; journal tag joan-clat.
3. Bench vs this SIM (proven-good v6 path): before/after literal-IPv4 reachability.
4. README: v6-only SIM quirk + what CLAT covers; per-carrier PDN family notes
   (cf. China Unicom IMS PDN study, Deck #111).

Not started - banked pending current agent wave + usage pool. Est: small pkg + 1 bench run.
