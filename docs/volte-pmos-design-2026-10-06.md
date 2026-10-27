# VoLTE on postmarketOS for the LG V30 — design (2026-10-06, Ember)

Direction (Lance, 2026-10-06): follow what AOSP 17 does and what LG does, adapt it
to how postmarketOS does things, and use the VoLTE-capable pmOS devices for help.

## What each reference actually does

**pmOS VoLTE devices (sdm845 etc.)**: `soc-qcom-modem` pulls `81voltd`, `msm-modem`,
`msm-modem-uim-selection`, `q6voiced`. The *modem firmware* runs the IMS client
(QMI IMSA/IMSS services). 81voltd gives it the IMS PDN, ModemManager places
calls over QMI Voice, the modem carries them over VoLTE, and q6voiced routes
the audio through the ADSP. The Calls app works unchanged.

**The V30 modem does not do that.** `qrtr-lookup` on the bench (fresh install)
shows no IMSA (33), IMSS (18) or IMSP (31) on node 0. It has Voice (9), WDS,
NAS, UIM, WMS, the vendor services 700-707/800 (v2, instance 1) and the AP-hosted
IMS data service 770 (81voltd). `qmicli --imsa-*` fails with "Internal".

**LG stock**: IMS runs on the AP (LG `libims`, Ims6.apk carrier configs, ~155
carriers). The modem provides the IMS PDN, radio and (via the vendor services)
helper functions.

**AOSP 17**: the same split through `ImsService` (MmTel feature, registration,
sec-agree). Our LineageOS port (`joan-volte-lineage`, an AOSP ImsService with
IpSecManager sec-agree) already does MO and MT calls with two-way audio on this
phone (T-Mobile; Digi.Mobil RO register+call).

So the V30 follows the LG/AOSP model: **AP-side IMS**. The pmOS-device model
(modem-side IMS) only applies if the modem's own IMS client can be switched on.
That is unproven, and it is tracked as an alternative below.

## pmOS adaptation

| Role | AOSP 17 | LG | pmOS (proposed) |
|---|---|---|---|
| IMS PDN | DataService, `ims` APN | imsdatadaemon | 81voltd + a ModemManager IMS bearer (apn=ims, ipv6, multiplexed), brought up by joan-imsd itself |
| Identity | ISIM via UiccController | libims | joan-imsd reads the ISIM over QMI UIM (exists; cache in /var/lib, mode 600) |
| Register / AKA / sec-agree | ImsService | libims | joan-imsd (REGISTER, AKA, userspace ESP exist); kernel xfrm later |
| Call control ↔ UI | ImsService ↔ Telephony | LG telephony | **new GNOME Calls provider plugin `ims`** ↔ joan-imsd over D-Bus |
| Media | app RTP | LG RTP | Calls' SIP media pipeline (GStreamer RTP ↔ PipeWire), already in `libsip.so` |
| SMS over IMS | ImsSmsImpl | libims | joan-imsd SIP MESSAGE (3GPP 24.341) → ModemManager-style messages for Chatty (later) |

The Calls provider is the AOSP-shaped seam: Calls already loads `mm`, `sip`,
`ofono` and `dummy` providers. An `ims` provider is to Calls what an ImsService
MmTel feature is to Telephony.

## Order of work (each step bench-gated)

1. **joan-imsd service hygiene** (no call behaviour change):
   - bring up or find the IMS bearer by APN, not `mmcli -b 2`;
   - take the interface from the bearer, not `qmapmux0.1`;
   - accept any global IPv6 address on that interface (drop `2607:`);
   - look up the WDS QRTR port (`qrtr-lookup`) instead of using a fixed (0,57);
   - unit: drop the `/etc` isim.env gate; read the ISIM at start; keep the
     StartLimit bounds.
   *Bench*: REGISTER 200 on a fresh install with no manual steps (no dialling).
2. **D-Bus API** on joan-imsd: registration state, Dial(number), Answer,
   Hangup, incoming-call and call-state signals. Keep the 480 decline whenever
   no UI client is connected (r5 behaviour).
3. **Calls `ims` provider plugin** (C, modelled on `plugins/provider/sip`), using
   its media pipeline for RTP.
   *Bench, needs Lance*: MO call to a test number, MT call from Lance's other
   phone, two-way audio.
4. SMS over IMS (MESSAGE in/out) → Chatty. *Needs Lance*: a test SMS.
5. Upstreaming notes: the provider plugin could serve any AP-IMS phone.

## Alternative, worth one bench session: modem-side IMS
If the MPSS firmware carries the Qualcomm IMS client but LG keeps it off, a
carrier MCFG/MBN selection (Persistent Device Configuration service 36 is
present) or the IMS-enable NV items could turn it on, and the stock pmOS stack
(81voltd + ModemManager + q6voiced) would then just work. Check this read-only
first: list PDC configs (`qmicli --pdc-list-configs`) and compare with LG's
`mcfg_sw` set. Writing configs or NV needs Lance's go-ahead.

## Safety rules carried forward
- Never auto-answer (r5). Never dial without Lance. Identity values never logged.

### PDC read-only result (2026-10-06 04:30)
`qmicli --pdc-list-configs=software` lists 7 MCFG configs: **TMO (Active, 21808 B,
v0x8010510)**, Commercial-US_Cellular ×2, **hVoLTE-Verizon ×2 (53076/53204 B)**,
CCA, ATT. The active TMO config is small next to the hVoLTE ones, consistent
with LG's AP-IMS design on T-Mobile. Even with TMO active, no IMSA/IMSS service
exists. The next read-only step is to diff what each MBN sets (pull them through
the PDC `get-config-info` / EFS, or from LG's `mcfg_sw` in the KDZ) for the IMS
enable items. Activating a different config on a T-Mobile SIM changes radio and
carrier behaviour, so it needs Lance.
