# ADSP QMI death-window analysis — breadcrumb boot (Boot E, 2026-08-17)

Agent: Aurel (Hermes-Agent, deepseek/deepseek-v4-pro). Following Ember's
Lane B handoff. RAM-only fastboot boots from nest, nothing flashed.

## Context

Boots A–D established: the ADSP's QMI/glink transport wedges silently
2–4 min after boot in every mainline boot; kernel QMI traffic accelerates
it. The ADSP never answers select-instance (even with LG's 3 s timeout).
Kernel-side QMI/QRTR paths are healthy (modem edge runs 12+ h).

## Boot E setup

- Kernel: 7187fbbb5 + K175 (re-arm up_worker) + K176 (3 s timeout)
  + K177 (JOAN-DBG breadcrumbs).
- Image: `boot-joan-qmidbg.img` sha256 f27dbac18129155212f88c6c19b076993663d2ac73f5ebe206cfad75ed95c414.
- Breadcrumbs: glink edge+channel on rx_open/rx_close, channel name in
  intent-request timeout, IPCRTR up/down, PDR notifier events,
  slim-ngd server up/down + up_worker progress, remote intent-req grants.
- Evidence: `evidence/2026-08-17-qmi-boots/qmidbg-dmesg-full.txt` (57 lines
  since the ADSP mark, 25 intent-request timeouts).

## Boot E timeline (kernel time)

| t (s) | event |
|---|---|
| 31.04 | ADSP start (mark) |
| 31.44 | fastrpc/IPCRTR/LOOPBACK_CTL_LPASS/glink_ssr channels open; QRTR up; PDR new_server 66/74; register-listener OK |
| 31.48 | PDR indication state UP |
| 31.50 | SLIMbus QMI server 769 up (node 5 port 11); up_worker proceeds |
| 31.57 | apr_audio_svc rx-intent req from remote (granted) |
| 43.74 | select-instance txn timeout (-110, 3 s) |
| 44.77 | QMI wait timeout (see mystery below) |
| 114.66+ | IPCRTR intent-request timeouts every ~13 s, forever |

## Boot E findings

1. **The ADSP's QMI stack comes up cleanly.** IPCRTR opens, all services
   announce, PDR register-listener is answered in ~50 ms. Nothing is
   broken at the protocol level in the first seconds.

2. **select-instance is sent ~9.7 s after the up_worker proceeds**
   (31.50 -> 40.74) and is never answered. The 3 s timeout is moot: the
   ADSP's slmb task is already not answering by t+10 s.

3. **The ADSP goes silent WITHOUT closing anything.** No del_server, no
   glink channel close, no IPCRTR-down breadcrumb ever fires. This is not
   a re-registration flap and not a crash (rproc stays running, no SMP2P
   fatal). It is a silent stop.

4. **The wedge mechanism on the wire: intent-request timeouts.** From
   ~114 s, every AP->ADSP send blocks exactly 10 s in
   qcom_glink_request_intent and times out. The ADSP stops granting the AP
   RX intents entirely. The repeating timeouts are the observer's own
   QRTR lookups: each lookup makes the kernel QRTR name service broadcast
   over IPCRTR; each broadcast blocks 10 s; the ns worker serializes, so
   every lookup client times out — which is why the observer saw
   "Terminated" and 769-as-absent from ~t+72 s observer time.

5. **The same edge stays healthy on other channels.** APR and glink_ssr
   show no timeouts; the only remote intent-req ever seen was
   apr_audio_svc (granted). The disease is specific to IPCRTR.

6. **Mainline's default rx-intent pool for a DTS-less channel is
   5 x 1 KiB** (qcom_glink_announce_create defaults). IPCRTR gets only
   that pool for the ADSP's inbound traffic; APR gets 512 x 20 B via
   qcom,intents. The ADSP sent its boot announcements using those 5
   intents with no intent requests — consistent with a small pre-granted
   pool.

## Open mystery (to be settled by Boot F)

"QMI wait timeout" at 44.77 s requires reinit_completion(&ctrl->qmi_up),
and the only reinit site is del_server — whose breadcrumb never printed.
Either a worker interleaving I can't see without per-worker logging, or
del_server ran without printk (unlikely). Boot F adds wait-enter/return
breadcrumbs to disambiguate.

## Disease model (current)

The ADSP's IPCRTR service dies silently ~40–100 s after ADSP start
(slmb answers nothing from ~10 s). Traffic accelerates it (Boot D: zero
QMI traffic, death at ~231 s). Candidate mechanisms, ranked:

1. **Intent-pool drain / lost RX_DONE.** With 5 x 1 KiB default pool on
   the ADSP->AP direction and a small ADSP-granted pool on the AP->ADSP
   direction, a single lost RX_DONE or intent collision permanently
   shrinks a pool; busy bidirectional churn at boot makes a leak likely.
   Boot F measures grants/RX_DONE directly.
2. **ADSP-side QMI task hang** that spreads from the slmb task (wedged at
   ~10 s on select-instance) to the shared QMI dispatch ~30–90 s later.
3. **Unbound-channel side effects:** ruled out — LOOPBACK_CTL is an
   AP-driven QA channel (downstream loopback server pings the ADSP, not
   the reverse); fastrpc channel is quiet and AP-initiated; glink_ssr IS
   bound in mainline.

## Next: Boot F (intent accounting)

Breadcrumbs added (v2 patch): every intent granted by the remote, every
intent advertised by the AP, every RX_DONE sent, every inbound data
message (rate-limited), riids pool count at each intent-request timeout,
up_worker wait-enter/return. Expected answers:
- Does the ADSP grant a finite pool that then stops replenishing?
- Does the AP's RX_DONE recycling stop at some point?
- Which pool hits zero first, and does that precede the first timeout?

Patch: `out/qmi-rearm-3s-breadcrumbs-v2-2026-08-17.patch`
sha256 0b58696700b158d5d7c8d236cf6adbed7559bf3e2b1b59ac9a9e0dd1ff6c6180.

## Boot G (qmidbg3g): gates prove the freeze is not select-instance/PDR

v3 kernel (intent accounting + version breadcrumbs + two gates), both
gates ON (slimbus.skip_select=1 pdr_interface.skip_listener=1):

- The ADSP DOES send RX_DONE_W_REUSE — but exactly 5, all within the
  first 5 ms of the IPCRTR channel's life (31.208-31.213). Then silence,
  forever. The gates did NOT prevent the freeze; they only removed the
  extra traffic, delaying pool exhaustion from 119.8 s (Boot F) to
  168.2 s (Boot G, first intent-request timeout, 44 timeouts total).
- Version negotiation: lpass edge remote version 1 features 0x7; ack
  features 0x1 (INTENT_REUSE) — matches ours. No negotiation loop.
- **Freeze onset is 31.213025 s** (last rx_done received). The ADSP's
  APR side is ALIVE after that: it answers the q6afe/q6asm
  get_svc_api_info probes at ~31.33 s. Only the IPCRTR/QMI side freezes.
- The freeze lands 20 us before the first APR service announcement
  (4:3 q6core at 31.213045). Coincidence or cause — Boot H discriminates.
- Refined disease model: the ADSP's QMI transport (csi_xport over
  IPCRTR) stops consuming AP traffic at the moment its service-
  registration burst completes (~31.21 s after start). From then on it
  never sends RX_DONE, never grants intents, never answers requests —
  but its APR transport keeps working. The 2-4 min "wedge" seen in
  earlier boots is pool exhaustion: exactly 30 AP->ADSP messages
  (observer ns-broadcasts + QMI sends), one per ADSP-granted intent,
  with zero returns.

## Boot H (qmidbg4h): APR registration gated

apr.skip_devices=1 (no APR service devices, no q6 driver probes, zero
APR interaction). All other interactions default. Discriminates:
APR-interaction-triggered freeze vs firmware-internal freeze.

Patch v4: `out/qmi-rearm-3s-breadcrumbs-v4-2026-08-17.patch`
sha256 be84d361d80b56e72677f01e720c5d1670d1cad7d86359d0739dea492e86b7a4.

## Firmware RE (approved by Lance 2026-08-17)

- adsp.mdt + b00-b11 banked in `fw/adsp/`; `fw/merge_mdt.py` merges the
  split MDT into `fw/adsp-merged.elf` (12,279,808 bytes; phdr index
  N -> adsp.bNN, 0-based; b07/b10 empty).
- Ghidra 11.4.3 + CUB3D/ghidra-hexagon-sleigh v0.6.1 extension installed
  at ~/vibe-coding-projects/coding/tools/ghidra (language ID
  "QDSP6:LE:32:default"). Import + auto-analysis headless.
- Anchors: b05 strings "Could not notify RX Done in channel %s@%s",
  "Dropping intent req (size=%d) for unknown channel(rcid=%d)",
  "glink_core_intent.c"; task names audio_pd, servreg, slimbus_qmi,
  qmi_fw, lpass_q6core; QMI transport "Lkqmi_csi_xport_ipc.c".
- Goal: find the IPCRTR transport's post-registration state machine and
  what it blocks on at ~31.2 s.

Assisted-by: Hermes-Agent:deepseek/deepseek-v4-pro
Date: 2026-08-17
