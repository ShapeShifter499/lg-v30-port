# ADSP QMI 769 bring-up: static analysis before device experiments

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:deepseek/deepseek-v4-pro
Date: 2026-08-17

Companion to `docs/NEXT-SESSION.md` (Lane B: audio, ADSP QMI). Everything
below is derived from the kernel tree at `7187fbbb5`, the evidence banked
under `docs/evidence/2026-08-16-*`, and the downstream LG tree
(`android_kernel_lge_msm8998`). No device was contacted.

## 1. Transport map: why APR is healthy while QMI fails

QMI/QRTR to the remotes rides the rpmsg channel literally named `IPCRTR`:

- `net/qrtr/smd.c` is an rpmsg driver matching device name `IPCRTR`
  (`qcom_smd_qrtr_smd_match`). It registers a QRTR endpoint with
  `QRTR_EP_NID_AUTO`.
- `drivers/rpmsg/qcom_glink_native.c:1681` names rpmsg devices after the
  glink channel the remote opens. So each remote that opens an `IPCRTR`
  glink channel gets a QRTR endpoint with a dynamically assigned node id.
  This is why the modem appears as node 0 in the WLAN boot and the ADSP as
  node 5 in the audio boot — node ids are per-endpoint, not per-remote.
- APR uses the `apr_audio_svc` channel on the same lpass edge. Different
  channel, different rpmsg device. **APR working proves only the lpass edge
  and the APR channel, not the QMI channel.**

Kernel config: `CONFIG_QRTR=y`, `CONFIG_QRTR_SMD=y`, glink built in.
There is no other QRTR transport on this platform.

## 2. The NGD driver's bring-up has a one-shot window

`drivers/slimbus/qcom-ngd-ctrl.c`:

- `qcom_slim_ngd_up_worker()` is scheduled from exactly two events
  (`qcom_slim_ngd_ssr_pdr_notify`):
  1. `QCOM_SSR_AFTER_POWERUP` for "lpass" — fired by
     `drivers/remoteproc/qcom_common.c` `ssr_notify_start()` exactly once
     per remoteproc start, at the moment "remote processor adsp is now up"
     is logged. I.e. t0.
  2. `SERVREG_SERVICE_STATE_UP` via the PDR status callback — only reachable
     with the pd_mapper fix (7187fbbb5) in place, because before it
     `pdr_locate_service()` returned -ENXIO and the lookup stayed pending
     forever (no locator re-appearance to re-run it).
- The worker waits **1 second** (`msecs_to_jiffies(MSEC_PER_SEC)`) for
  `ctrl->qmi_up`, which is completed only by
  `qcom_slim_ngd_qmi_new_server()` when QMI service 769 appears.
- **`qmi_new_server()` does not schedule the up_worker.** If 769 registers
  after the 1 s window closes, the completion fires into the void and the
  NGD never enables. There is no retry.

The 1 s timeout itself is deliberate upstream behaviour (lkml
`slimbus: qcom-ngd-ctrl: Add timeout for wait operation`, 2024-04-30 —
the previous infinite wait deadlocked a kthread). The defect is that
nothing re-triggers the worker when the server finally appears.

Measured 769 arrival times relative to remoteproc-up on joan: session A
"within ~4 s" (good boot), sometimes under 1 s (session A flaky boot
caught it, then hit a separate 1 s `SLIMBUS_QMI_RESP_TOUT` timeout on
SELECT_INSTANCE). On sdm845 boards the ADSP auto-loads and 769 lands
inside the window, which is why upstream does not bite there.

**Consequence: on joan the NGD coming up is luck.** The 1 s SSR window
starts at t0; the PDR trigger (post-fix) fires ~40 ms after t0 (state-UP
indication) — still long before a slow 769. This alone explains session A's
good/flaky split and session B boot1's "QMI wait timeout" pair: in boot1
the PDR trigger worked, the indication came at t0+40 ms, and both windows
closed before 769 would have arrived.

## 3. What remains unexplained: session B boot2

Boot2 (ADSP started at 33 s) shows a different failure than a missed
window:

```
[34.408516] qcom,slim-ngd-ctrl 171c0000.slim-ngd: QMI wait timeout
[38.628673] PDR: msm/adsp/audio_pd register listener txn wait failed: -110
```

- The register-listener txn (5 s timeout, `pdr_register_listener()`) was
  sent at ~33.6 s and never answered. The QRTR send itself must have
  succeeded (otherwise `qmi_send_request()` fails immediately and we would
  not see a txn-wait timeout), so the IPCRTR channel was open.
- The ADSP announced servreg-notif (66, instance 74) — that is what
  triggered `pdr_notifier_new_server()` — then did not answer the
  register-listener for 5 s. In boot1 the same exchange completed in
  ~40 ms (indication received at t0+40 ms).
- 769 was polled absent for 30 s after ADSP start (t+3..t+30 s).

So boot2 is not "missed the window", it is "the audio PD's QMI side was
unresponsive at early boot". The AP-side environment differs from boot1
only by start time (33 s vs 391 s) — deferred probing is still live at
33 s (`deferred_probe_timeout=300`), the modem is down in both boots.

Boot1's evidence does NOT prove 769 never registered: the only lookup was
taken ~2 s after ADSP start, and both up_worker windows had closed by then.
769 at ~4 s (as in session A) would have been missed entirely.

## 4. The pd_mapper fix as a behavioural change (7187fbbb5)

The commit changes two kernel behaviours:

1. The AP now answers `SERVREG_LOC_GET_DOMAIN_LIST` with the ADSP/SLPI
   domains (before: empty list). The ADSP's servreg task builds its
   service→domain table from these answers, so the firmware now sees a
   non-empty (but `tms/servreg`-less) answer.
2. The NGD's PDR lookup for `avs/audio` now succeeds, so the kernel sends
   `SERVREG_REGISTER_LISTENER` to the ADSP at audio-PD boot and handles the
   state-UP indication — traffic that never existed before the commit.

Either could disturb the ADSP's audio-PD init on this LG firmware. Both
are cheap to test. Note `adspua.jsn` (the firmware's own map) lists
`avs/audio` AND `tms/servreg` for the audio PD; the kernel's
`adsp_audio_pd` struct lists only `avs/audio` — same shape as every other
SoC in the table, so probably inert, but it is a known delta.

## 5. Candidate fixes / experiments (host-prepared, device runs need Lance)

A. **Driver robustness (upstream-candidate shape):** schedule
   `ngd_up_work` from `qcom_slim_ngd_qmi_new_server()` (or otherwise
   re-arm the wait) so a late 769 still brings the NGD up. Minimal diff in
   `drivers/slimbus/qcom-ngd-ctrl.c`. This addresses the structural
   fragility regardless of what the ADSP does.

B. **Discriminator for the pd_mapper commit:** same tree with 7187fbbb5
   reverted (-4 lines), boot with the standard early-start flow, poll 769
   for 60-90 s. If 769 returns, the commit interacts badly with the audio
   PD; if not, the flakiness is elsewhere.

C. **Observation/instrumentation:** if B is negative, add dev_info
   breadcrumbs to `net/qrtr/smd.c` (IPCRTR open/close) and
   `pdr_interface.c` (notifier new/del server, txn start/end) — debug-only
   class, never upstream — to watch the channel and transaction lifecycle
   across a 33 s start.

Proposed boot order: A first (with 60-90 s of 769 polling — this also
answers whether boot1's absence was late arrival), then B as the control.
If both positive for 769, land A as the fix; if A positive and B negative
(i.e. 769 only comes back without the commit), dig into the commit's
interaction before landing A.

## 6. Not re-deriving (ledger traps)

- Build in place in `/data/buildcache/kbuild/build-adsp-only`, no `cp -a`,
  no added KCFLAGS; read `.<obj>.cmd` before assuming flags.
- RAM boots only; ADSP start does not survive a phone reboot; rebuild the
  USB net link by hand after every re-enumeration.
- `deferred_probe_timeout=300` (never 0), keep ATH10K_DEBUG/DEBUGFS off in
  any image that must keep Wi-Fi.
- Fresh boots only for audio judgements — never judge from an ADSP restart.
- Don't trust `grep -c` self-matches; verify the image's own version
  string.

Assisted-by: Hermes-Agent:deepseek/deepseek-v4-pro
Date: 2026-08-17
