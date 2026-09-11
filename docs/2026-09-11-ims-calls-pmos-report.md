# Report: calls/VoLTE on pmOS — state, gaps, and the path to two-way (2026-09-11)

Investigation: Fulgor (ZCode:zai-coding-plan/GLM-5.3), Explore agent run on
2026-09-11. STANDING APPROVAL (Lance): always look at the code and reverse
engineer stock ROM/kernel wherever it helps the port.
Sources cited inline; agent token count ~2.4M across 58 tool calls.

## Executive summary

A **MO VoLTE call was already completed from pmOS on 2026-08-26** (SIP
REGISTER 200 → INVITE → 180/200 → ~11 s of one-way PCMU audio → BYE,
verified by the recipient — `lg-v30-joan-pmos-packages/HOW-VOLTE-WORKED-2026-08-26.md`),
and the sibling LineageOS lane has since shipped a **fully working two-way
implementation** (REGISTER, MO/MT calls, two-way PCMU audio, hold, call
waiting, verified on LineageOS 22.2). The architecture is settled and is
*not* the one the stock ROM uses: **joan's modem has no IMS stack at all**
(verified from the stock ROM), so IMS must be entirely AP-side — SIP +
ISIM-AKA + IPsec + RTP in Linux userspace, with the modem contributing only
the bearer and QMI UIM. That means the kernel q6voice/CVD work is a parallel
track, **not** on the critical path for VoLTE calls. What remains on pmOS is:
kernel IPsec (currently off in the shipped config), MT-call fixes (three
known stacked bugs), a real RTP↔PipeWire audio bridge (mic capture now works
as of 2026-09-11), registration-robustness code that already exists in the
LOS lane, and dialer glue.

## 1. What joan-imsd implements today (verified from source)

Package: `pmaports-lg-v30-clean/device/testing/joan-imsd/` (APKBUILD r3;
depends `python3 qmi-utils modemmanager 81voltd`). Runtime
`joan_ims_live.py` (967 lines) run as `joan-ims register|dial`:

- **QMI over QRTR, raw sockets** (`joan_ims_live.py:45-101`):
  `wds_pcscf()` sends QMI WDS Get Current Settings (0x002D) to qrtr node 0
  port 57 and extracts the **P-CSCF IPv6 list from TLV 0x2E** plus gateway
  (TLV 0x26). `vss_set_ims_registered()` — QMI 0x0707 to qrtr port 73, a
  status *set* to the modem's proprietary VSS service (does not start SIP).
- **ISIM via QMI UIM through qmicli subprocesses**: logical channel AID
  A0000000871004…, EF-IMPI/EF-DOMAIN/EF-IMPU, **ISIM AUTHENTICATE APDU
  0088008122** for IMS-AKA (RES/CK/IK) (`joan_ims_live.py:129-255`).
- **ModemManager/mmcli** for the IMS bearer (`qmapmux0.1`), IMEI, MSISDN.
- **SIP over UDP inside userspace ESP**: AF_INET6/SOCK_RAW/IPPROTO-50 with a
  **pure-Python AES-128-CBC + HMAC-SHA1-96 ESP implementation**
  (`joan_ims_esp.py`). `joan_ims_ipsec.py` can *print* `ip xfrm` commands
  but the live flow does not apply them.
- **RTP: send-only PCMU from a fixed file** — no capture, no playback, no
  RTP receive/jitter buffer, no RTCP, no AMR. Lab placeholder.
- Signalling: deregister → REGISTER#1 unprotected → 401 + Security-Server →
  ISIM AKA → REGISTER#2 inside ESP SA with Security-Verify + RFC 3310 → 200
  OK → Service-Route → VSS → MT loop or dial (INVITE w/ PCMU/AMR-WB/AMR/
  telephone-event SDP, 100rel/PRACK, ACK, RTP file loop, BYE).
- **Not implemented**: re-REGISTER timer, P-CSCF failover (uses pcs[0]),
  TCP transport (`TPT_NEEDS_TCP_OVER_XFRM`), MT robustness, SMS-over-IMS.
  Carrier profile layer (`joan_ims_profiles.py`, 164 entries from stock
  Ims6.apk) resolves full PLMN — the LOS audit's MCC-only defect (E) does
  not apply here.
- Verified on hardware: REGISTER 200 + MO INVITE + one-way PCMU on T-Mobile
  US, 2026-08-26. **MT never delivered** (three stacked bugs, §2c-2).

## 2. Architecture question, settled with evidence

`docs/2026-08-23-cellular-data-gsi-uplink.md` (CORRECTION/Conclusion):
**the modem registers zero IMS QMI services** (18/19/31/32/33/40 absent
from QRTR; no IMS executable in stock; LG's IMS is HIDL+Java in the Android
framework). "VoLTE on joan requires implementing the AP-side IMS stack."
Preconditions verified: ISIM on the SIM; IMS APN = modem profile index 10.

Both working lanes use **AP-side RTP**, not the modem vocoder:
- pmOS 2026-08-26: "Media was AP PCMU, not q6voice/AMR".
- LOS `joan-volte-lineage/README.md`: org.joan.ims ImsService does
  "REGISTER, INVITE/ACK/BYE, PCMU RTP, RTCP SR+SDES" with
  setCallAudioHandler(ANDROID) → platform voice stream feeds the app's own
  RTP. "Working on LineageOS 22.2: IMS REGISTER 200, Dialer outbound and
  inbound PCMU calls, two-way audio, hangup from either side."

### The kernel q6voice/CVD work — real, verified, but NOT on the critical path

`sound/soc/qcom/qdsp6/q6voice.c` (608 lines on joan/wake-path-v1) is a
debugfs-driven CVD probe: MVM(0x09)/CVS(0x0A)/CVP(0x0B) APR services, full
CREATE_PASSIVE_CONTROL_SESSION / ATTACH_STREAM /
CREATE_FULL_CONTROL_SESSION_V2 (AFE SLIMbus ports 0x4000/0x4001,
topologies 0x10F77/0x10F71) / ENABLE / ATTACH_VOCPROC / START_VOICE + reverse
teardown. Commits 22c063a3f4c5, 3dc2687f381a, 02aad3751629; DT nodes at
msm8998.dtsi:3792-3803. Hardware-verified: all services bind, all 7 steps
status 0, four clean cycles. Open bug: module reload silences the ADSP;
fix exists as `5f6732fb6cb8` on `joan/q6voice-mvm-probe`, NOT on
wake-path-v1. Shipped kernel config has neither this driver nor
XFRM_USER/INET_ESP/INET6_ESP (all unset).

Assessment (strongly supported): with the AP-side-IMS architecture actually
shipped, the modem never gets RTP, so **q6voice is not needed for a pmOS
VoLTE call**. It matters only for CS voice (T-Mobile US has none) or a
future modem-media design. Separate, non-blocking track.

## 3. Concrete gaps for a completed two-way call on pmOS

1. **Kernel IPsec**: enable `XFRM_USER`, `INET_ESP`, `INET6_ESP` as
   **modules** (Librem 5 pattern; two earlier built-in attempts oopsed —
   HOW-VOLTE-WORKED §2). Userspace ESP is UDP-only: no TCP transport, no
   P-CSCF ESP keepalive answers.
2. **MT path** — three stacked bugs (§1.7): Contact used an IPv6 privacy
   address (fix: stable GUA, disable tempaddrs on the IMS iface); 84-byte
   P-CSCF ESP keepalives on spi-s ignored; TCP-in-ESP unsupported. All
   have known fixes; none implemented in joan-imsd.
3. **RTP ↔ audio bridge**: G.711 encode/decode loop (20 ms ptime), RTP
   receive + jitter buffer, PipeWire in/out. Raw material exists: mic
   capture works (2026-09-11), UCM Mic/Headset devices, WebRTC echo-cancel
   virtual source packaged (`50-joan-echo-cancel.conf`) — necessary because
   mainline q6adm has no ACDB: all conditioning is userspace (LOS found the
   same, added software AGC/limiter at −20 dBFS).
4. **Registration robustness** — proven in LOS lane, absent in joan-imsd:
   re-REGISTER at 80% of expiry (core grants 3600 s vs requested 600000),
   P-CSCF failover across the advertised list, inbound CANCEL (else every
   later call is 486), OPTIONS answering, ACK identity repair (alpha10),
   IP-family flip, Security-Verify/494. LOS audit found 5 production
   defects (A–E) + 2 ABI mismatches — port the FIXED logic
   (`~/.hermes/workspace/reviews/joan-ims-audit-2026-09-07/report.md`).
5. **Dialer/UI**: `calls` (Phosh) drives ModemManager CS voice; T-Mobile US
   has no CS. MM upstream has no IMS-voice API. Short term: D-Bus/CLI dial
   on joan-imsd (`joan-ims dial` exists).
6. **Codecs**: PCMU proven against the live T-Mobile core; AMR-WB is the
   quality win some cores require (opencore-amr/vo-amrwbenc — optional).
7. **Identity UX**: systemd unit is inert until
   `/etc/joan-imsd/isim.env`; run the ISIM read on first boot instead.

## 4. How other mainline projects do VoLTE — and why joan differs

- **OnePlus 6 / Pixel 3a / SC7280 (pmOS mainstream)**: `81voltd` (GPL RE of
  the IMS Data service, packaged in pmOS + Debian) — there the *modem* runs
  IMS; calls via ModemManager; audio via kernel q6voice + q6voiced. On joan,
  81voltd is used **only** to bring up the IMS PDN (verified working,
  joan-audio-session-2026-08-25 journal), because joan's modem has no IMS.
- **msm8916-mainline**: out-of-tree q6voice (Minecrell) + q6voiced for
  CS-call audio; pmOS-financed rework toward upstream (pmOS blog 2026-05-08).
  No SIP component — those modems run IMS themselves. Joan is the opposite
  case, which is why CAF OpenIMSd / org.codeaurora.ims are explicitly the
  wrong architecture ("Do not ship it" — HOW-VOLTE-WORKED §0).
- **ModemManager upstream**: no IMS voice-call support. Sailfish/Ubuntu
  Touch VoLTE efforts ride vendor RIL/modem IMS — not applicable to
  mainline joan.
- **Minimal architecture that works (proven on this handset)**: IMS PDN
  (81voltd/MM, qmapmux0.1) → P-CSCF from QMI WDS TLV 0x2E → REGISTER +
  ISIM-AKA (QMI UIM) → 3GPP IPsec ESP transport → SIP INVITE → **AP-side
  G.711 RTP over a normal audio stream** with userspace echo cancellation.
  No CVD, no modem RTP.

## 5. Ordered plan to a first outgoing call on the shipping image

**M0 — Registration on the shipping image (mostly existing work)**
1. Kernel config: XFRM_USER/INET_ESP/INET6_ESP as modules. Config-only.
2. Packaged `joan-imsd register` live on T-Mobile: first-boot ISIM read +
   81voltd IMS PDN + WDS TLV 0x2E P-CSCF + REGISTER 200 (all proven
   2026-08-26). Soften the ConditionPathExists gate.
3. Port from LOS alpha13 (test-covered): expiry refresh, P-CSCF failover,
   inbound CANCEL, OPTIONS. Apply the audit's fix-then-port ordering.

**M1 — MT ring** (all fixes documented)
4. Kernel xfrm SAs/policies UDP+TCP (joan_ims_ipsec.py prints them);
   stable GUA on IMS iface; answer P-CSCF keepalives; TCP-in-xfrm.

**M2 — Two-way voice**
5. joan-imsd: RTP receive + jitter buffer; G.711 loop wired to PipeWire;
   uplink from joan_echo_cancel_source; port the LOS AGC/limiter.
   *Principal genuinely new code.*

**M3 — Dialer**
6. D-Bus dial/answer/hangup on joan-imsd + minimal Phosh-callable UI.
   Never route through MM CS voice on T-Mobile.

**Parallel, non-blocking**: q6voice track — cherry-pick `5f6732fb6cb8`
(remove callbacks) onto wake-path-v1, debug the module-reload ADSP silence,
enable CONFIG_SND_SOC_QDSP6_VOICE; keep off the VoLTE critical path.
