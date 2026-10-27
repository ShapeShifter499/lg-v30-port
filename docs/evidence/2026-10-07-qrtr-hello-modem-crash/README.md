# qrtr "Send HELLO message on endpoint register" crash-loops the MSM8998 modem (2026-10-07)

Ember (Claude-Code:claude-opus-5-5). Bench: US998, pmOS from SD, RAM boots via ramboot.sh.

## Symptom

On the r59 bench candidate the modem (MPSS) raises `fatal error without message`
~42 s after every start (first at 57.6-58.9 s after boot, then every ~41.8 s:
141.4, 183.2, 225.0, 266.7 s), each followed by `port failed halt` (IPA). Within
one to several cycles pmOS dies (panic=5 -> the phone comes back up in
LineageOS); pstore is empty, the persistent journal just stops. ModemManager
never sees a QMI port ("at least a QMI port is required").

## Isolation (persistent journal, boot by boot)

| boot | kernel image | modules on SD | front cam (HI553) | modem crashes |
|---|---|---|---|---|
| 04:59-10:43 | r57 | r57 | none | 0 in ~6 h |
| 11:42-11:49 | r59+EM | r59 | 0x28, fails probe | 0 in 7 min |
| 11:49-11:54 | r59+EM | r59 | 0x20, probes | 7 (first 57.9 s) |
| 12:00-12:03 | r59+EM | r59 | 0x20, 4-lane | 4 (first 58.9 s) |
| 12:14-12:20 | r59+EM | r59 | 0x20 | 5 (first 58.3 s) |
| 12:24-12:25 | r59+EM | r59 | node removed | 1 at 57.6 s, then pmOS died |
| 12:32-12:35 | r57 | r59 | none | 1 at 58.7 s |
| 12:42-12:47 | r57 | r57 | none | 0 at 201 s (modem up in MM) |
| 12:47-12:48 | r57 | r57 + r59 qrtr.ko | none | pmOS died at ~43 s |

- The HI553 correlation was a coincidence: removing the node did not help.
- r57 kernel + r59 modules crashes; r57 + r57 modules does not; swapping in only
  r59's qrtr.ko brings the death back. qrtr.ko carries the three qrtr backports
  in r59 (544d85de4dc2 HELLO-on-register, ff194cffd586 / 7fc1c937b6b3 ns limits).
- The 7 crash-free minutes on r59 modules (11:42) mean the failure is a race that
  usually, not always, loses.

## Mechanism (from the commit, consistent with the timing)

544d85de4dc2 moves HELLO ownership from the name server to the core: one HELLO
per endpoint at registration, packets gated until it is sent, and the NS's
reply to an inbound HELLO removed "without a replacement". The commit targets
slave-role MHI WLAN remotes. The MSM8998 MPSS firmware evidently relies on the
old reply: it waits ~40 s for its handshake and asserts. Not yet proven which
part (lost reply vs. ordering gate) is fatal; reverting the whole commit is the
tested-safe state.

## Action

- r60 candidate = r57 + glink smem FIFO ordering (786439ad) + ns limits
  (ff194cff, 7fc1c937) WITHOUT 544d85de, + ath10k delete-key trio, rmnet
  IFF_NOARP, CPU Energy Model (+ .register_em fix). HI553 left out until it
  streams (CAMSS waits on every endpoint, so a disabled sensor node would break
  the rear camera).
- Upstream report candidate: 544d85de4dc2 regresses MSM8998 MPSS (post 7.2-rc2).

## r60 reboot loop (2026-10-07 14:05-14:17)

Six hands-free RAM boots of r60 (tools/bench/ramboot.sh, armed send), checked at
~92 s uptime each: 6/6 sound card present, 58 QRTR services, 0 modem crashes,
ModemManager modem present, 0 failed units. Dropping 544d85de4dc2 does not
bring back the ADSP sound-card race that the backport set was meant to fix (in
this sample).
