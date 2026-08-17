# ADSP QMI experiment matrix — four RAM boots, 2026-08-17

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:deepseek/deepseek-v4-pro
Date: 2026-08-17

Companion to `docs/aurel-2026-08-17-adsp-qmi-769-analysis.md`. Four RAM-only
boots (nothing flashed), each with a 90 s 769 poll, full qrtr-lookup, dmesg
since the ADSP-start mark, and a +60 s late re-check. Evidence in
`docs/evidence/2026-08-17-qmi-boots/`.

## Images

| tag | kernel | sha256 | release |
|---|---|---|---|
| qmia (Boot A) | 7187fbbb5 + patch A (re-arm up_worker) | `b5aa5619…35061` | `7.2.0-rc2-qmia-g7187fbbb5675-dirty` |
| qmit (Boot B) | qmia + 3 s SLIMBUS_QMI_RESP_TOUT | `c4f1349f…93658` | same string, differs by hash |
| qmit (Boot C) | same as B, modem-first flow | `c4f1349f…93658` | |
| qmir (Boot D) | qmit + pd_mapper commit 7187fbbb5 reverted | `5fe1fea2…459a` | same string, differs by hash |

All images: donor cmdline + `log_buf_len=8M deferred_probe_timeout=300`,
same DTB as the snd-pdm lineage, ramdisk byte-identical to the donor,
repack verified kernel==staged, one-shot hash-bound runners.

## Result matrix

| | Boot A (qmia) | Boot B (qmit) | Boot C (qmit, modem first) | Boot D (qmir, revert) |
|---|---|---|---|---|
| ADSP start | 33 s | 32 s | after modem up | 33 s |
| PDR listener | OK, ind @ +50 ms | OK, ind @ +40 ms | OK, ind @ +40 ms | lookup -6 (expected, pre-fix) |
| 769 appears | t+6 s | t+6 s | t+6 s | NEVER (90 s + late check) |
| servreg-notif 66/74 | yes | yes | yes | NO |
| select-instance | -110 @ 1 s | -110 @ 3 s | -110 @ 3 s | never attempted |
| 769 at 4 min | gone | gone | gone | n/a |
| glink intent timeouts | (not watched) | 115.9 s, 186 s | 114 s, 127 s, 197 s | 231 s |
| modem | down | down | up (TIME svc present) | down |
| ALSA card | no | no | no | no |

## Conclusions

1. **The pd_mapper commit (7187fbbb5) is HELPFUL, not harmful.** With it
   present, 769 and the ADSP's QMI services register (~6 s after ADSP
   start) in 3/3 boots; PDR listener registration succeeds. With it
   reverted (Boot D), the ADSP registered NO QMI services at all — not
   even servreg-notif — while APR was healthy. The commit biases the ADSP's
   QMI stack toward registering (plausibly because the ADSP's own domain
   lookups now get non-empty answers). Ember's boot1 "769 never appeared"
   was a measurement-window artifact; boot2's 30 s absence is the same
   flake Boot D shows, on a kernel that did carry the fix — so the fix
   helps but does not guarantee registration.

2. **Patch A (re-arm the up_worker on 769 new_server) works as intended.**
   In Boots A-C the NGD driver got past the qmi_up gate (previously a
   permanent dead end when 769 arrived after the 1 s window) and reached
   the select-instance step. The state guard prevented double-enable.
   This is a real defect fix in the driver regardless of the ADSP-side
   disease.

3. **The 3 s LG timeout is necessary but not sufficient.** Boot B proved
   the ADSP does not answer select-instance within 3 s either — the task is
   not slow, it is wedged.

4. **The modem does not gate the ADSP's SLIMbus path.** Boot C ran the full
   modem bring-up (rmtfs + MPSS + TIME service 22 present before the ADSP
   started) and select-instance still timed out, same wedge timeline.

5. **The ADSP's QMI/glink stack dies on its own, 2-4 minutes after boot,
   in this environment.** Boot D proves the wedge happens with ZERO
   kernel-side QMI traffic to the ADSP (no listener registration, no
   select-instance) — just ~2x slower (231 s vs ~114 s). Kernel QMI
   traffic accelerates the death but does not cause it. rproc1 stays
   "running" (no fatal, no SMP2P signal) — the DSP is alive; its QMI/glink
   side stops responding. APR services stay registered in dmesg (no
   re-registration = no PD restart). qrtr-lookup hangs once the edge is
   wedged.

6. **Session A's good boot (SLIM SAT + codec enumeration) is the only
   counterexample** and remains unexplained: same firmware, same
   audio-only flow, pre-fix kernel. Either that boot hit a lucky ADSP init
   window, or some uncontrolled variable (e.g. the phone's pre-fastboot
   state) protected it. One good boot out of nine attempts across all
   sessions.

## What this leaves open (next-session menu)

- The ADSP-side disease: why does the audio PD's QMI stack die in the
  mainline environment but run for days on LineageOS with the same
  firmware? Prime suspects, uninvestigated:
  * glink edge/QRTR setup differences vs downstream (intents per channel,
    edge configuration, SMEM layout for the lpass edge);
  * an AP-side QMI service or keepalive that stock provides and mainline
    does not (the ADSP's QMI router may garbage-collect its registration
    when it cannot reach something it expects);
  * ADSP LPM/power-collapse interaction: the ADSP idles down and never
    fully returns on the QMI path.
- Whether select-instance can EVER be answered in mainline: needs one more
  observation with kernel-side breadcrumbs (glink channel open/close,
  QRTR endpoint registration, QMI txn lifecycle) plus qcom_glink trace
  events, watching the exact moment the IPCRTR channel goes silent.
- Upstream-shaped patch A (the re-arm) is worth landing regardless: the
  one-shot 1 s window is a genuine driver defect that bit sdm845-class
  timing on slower firmware.

## Files

- `out/qmi-rearm-upwork-2026-08-17.patch` (patch A, sha256 `2aae35ef…5059`)
- `out/qmi-rearm-plus-3s-tout-2026-08-17.patch` (patch A + 3 s, sha256 `abe25c77…7013`)
- `out/revert-pdmapper-2026-08-17.patch` (forward diff of 7187fbbb5 for reverting)
- evidence: `docs/evidence/2026-08-17-qmi-boots/{qmia,qmit,qmitC,qmir}-*.txt`
- images (nym-nest): `boot-joan-{qmia,qmit,qmir}.img`, staging `staging/{qmia,qmit,qmir}`
- repack + runners: `~/joan-images/staging/{repack-qm*,*-ramboot-once.sh,cycle.sh,qmi-observe-inner.sh}` on nym-nest

Assisted-by: Hermes-Agent:deepseek/deepseek-v4-pro
Date: 2026-08-17
