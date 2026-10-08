# joan cellular RX stall — bench measurements (2026-10-07, linux-lg-joan r60)

Ember (Claude-Code:claude-opus-5-5). US998, T-Mobile US (IPv6-only bearer), RAM boots via
tools/bench/ramboot.sh, lg-joan-cellular-data r7 (CLAT, DAD hook).

## Symptom
ModemManager `connected`, NetworkManager `activated`, carrier IPv6 address and routes in place,
but the qmapmux link receives almost nothing (0-30 packets) and IPv6 never works.

## Frequency
10 of 16 r60 boots stalled at 120 s (then 4 of 4 in the last loop). One boot followed to 600 s:
no recovery. Once also on r57 (12:59). Earlier the same day several boots had working data
(r57 04:59 for hours; r59 11:42; r60 13:20, then 6/6 reboot loop not checked for data).

## What restores data
| remedy | result |
|---|---|
| NetworkManager reconnect (`nmcli con down/up`) | 0/2 |
| `rmnet_ipa0` down/up with the connection down (manual, ~120-130 s) | 1/3 (first success was luck) |
| same, automatic at ~91 s (joan-rx-check, reverted pmaports 1e2928707f) | 0/4 |
| IPA runtime PM forced on (`power/control=on`) on a boot-time stall | 1/4 |
| IPA runtime PM forced on when data had worked and then died at ~237 s | 1/1 |
| modem remoteproc stop/start | 1/1 (35 s) — but leaves Wi-Fi (ath10k) dead until reboot |

## Observations
- Stalled boots: `rmnet_ipa0` tx_dropped = 9 every time, qdisc backlog 0, requeues 16-52;
  IPA runtime status `suspended` at 120 s; the `ipa` interrupt fired only ~3 times per boot.
- A data-then-dead case: IPA stayed `suspended`, a ping produced no IPA/GSI interrupts and no
  resume; forcing runtime PM on restored IPv6 and IPv4 at once. On a healthy link the same
  probe shows suspend -> resume on TX -> reply -> suspend (500 ms autosuspend works).
- So two effects: (A) dominant, data never starts at boot; (B) data dies when IPA
  runtime-suspends and nothing resumes it.
- The boot path zeroes IPA modem memory (ipa_mem_setup) and both boot and restart reach
  ipa_modem_start() via ipa_qmi_ready(); the first boot additionally sends the QMI "init
  complete" indication (initial_boot).

## Next
Instrumented ipa.ko (it is a module; SD /lib/modules swap + reboot): log RX/TX endpoint and GSI
channel state, aggregation state and the 9 TX drops (where and why) at ipa_open, ipa_modem_start
and first traffic; compare a stalled boot, a good boot and a post-restart session.

## Later the same day (16:15-17:00): instrumented ipa.ko and two disproven hypotheses

Instrumented ipa.ko (branch joan/debug-ipa-rx-stall 179f3332dda0, bench only):
- The 9 TX drops per boot are IPv6 packets (proto 0x86dd) sent directly on rmnet_ipa0, which
  only takes QMAP frames: rmnet_ipa0's own IPv6 housekeeping. Benign.
- Boot order is identical on stalled and good boots: modem running ~16.5 s, QMI ready
  (modem_ready, uc_ready, initial_boot=1) -> ipa_modem_start ~16.8 s, ipa_open ~30.1 s.
  On stalled boots 3-17 downlink packets arrive right after ipa_open, then none.
- The "ipa" interrupt fires 2-3 times per boot.

| hypothesis | test | result |
|---|---|---|
| IPA IRQ (SPI 333) should be level, not edge (downstream uses type 0) | DTB with IRQ_TYPE_LEVEL_HIGH, 4 boots | 3/4 stalled; IRQ still 2-3 per boot. Disproven. |
| runtime suspend loses the wake | udev power/control=on from boot, 4 boots | 3/4 ok, 0 suspends on all, but boot 1 stalled with IPA never suspended. Not the cause (maybe a contributor). |

Root cause still open. Untested next ideas: the modem-side QMI exchange on first boot vs after
restart (the restart path also flushes/resets the modem filter/route tables and zeroes modem
memory before the next start); compare the IPA QMI init_modem_driver request contents between
first boot and post-restart.

## 17:00-18:00: more hypotheses tested

| hypothesis | test | result |
|---|---|---|
| RX ring drains (replenish/doorbell batching) | instrumented replenish, 3 boots | identical on stalled and good boots (249 queued at open, 1 per completion). Disproven. |
| bearer connected too early | autoconnect off, `nmcli con up` at 60 s, 4 boots | 3/4 stalled. Disproven. |
| my CLAT/DAD userspace (lg-joan-cellular-data 0.2) | downgrade to 0.1-r1, clatd removed, 4 boots | 2/4 stalled. Not mine. |
| band / carrier aggregation | qmicli rf-band + CA info, 4 boots | stalled and good boots on the same B66 cell. Disproven. |
| IMS data daemon (81voltd) sharing mux id 1 | 81voltd masked | first boot stalled. Disproven. |

Only consistent correlate: network attach time. Stalled boots attach ("packet service attached")
at ~28-30 s and open the IPA netdev at ~30-32 s; good boots attach at ~38 s and open at ~40 s
(11 boots). Forcing a late connect did not help, so the attach-time difference is a symptom of
modem-side state at attach, not a cause we control from the AP.

Bench note: scripted pmOS reboots dropped the phone off USB three times on 2026-10-07 (no
fastboot, no LineageOS) until a manual power-cycle.
