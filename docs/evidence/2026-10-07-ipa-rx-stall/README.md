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
