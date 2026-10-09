# joan cellular RX stall — 2026-10-09 retest (linux-lg-joan r60)

Aurel Nymvale (Hermes Agent, xai-oauth/grok-4.7). Continues
`docs/evidence/2026-10-07-ipa-rx-stall/README.md`. US998
`LGUS9986e606d55`, T-Mobile US, IPv6-only bearer, RAM boots of
`~/joan-images/r60/boot-joan-r60-ondevice.img` (sha256
`33fe1f506b0062a8878cd55b31851406918c467d3c0f7bfdc7e29712fc221332`)
via `tools/bench/ramboot.sh` (armed send, 420 s). Kernel
`#61-lg-joan` = `joan/latest-clean-test` `3f7fcabf` (r60 + CAMSS
csiN clock). `lg-joan-cellular-data` 0.2-r7 (CLAT).

Nothing in this note is a fix. No package was built from it.

## Two fresh boots, both stalled

| boot | boot_id | attach | result |
|---|---|---|---|
| 06:44 | `ebdb445a-df18-49d9-a11f-bba52d751b50` | 29.1 s | RX frozen at 11 packets / 3072 bytes through 242 s. Gateway ping 0/2. IPA IRQ 2. Sound card present. |
| 06:49 | `4d8130cb-1ec8-423d-ab35-93ba64759046` | 38.1 s | RX frozen at 23 packets by 90 s, 27 by 197 s. Gateway ping 0/2. DNS ping 0/1. IPA IRQ 1 at the 90 s sample. Sound card present before the restart below. |

Both boots: ModemManager `connected`, NetworkManager activated,
IPv4 `CallFailed` / `ip-version-mismatch` (expected on this SIM),
IPv6 settings installed, CLAT up, no downlink.

The 2026-10-07 correlate (stalled attach ~28-30 s, good attach ~38 s)
did not hold. A late attach is not a cure.

Host snapshots: nest `/tmp/joan-ipa-stall-20261009/boot0-snapshot.txt`
and `boot1-snapshot.txt`.

## Modem restart did not restore data

On boot `4d8130cb`, with Wi-Fi already disconnected, one
`remoteproc1` stop/start (modem, not ADSP):

- Kernel: `received modem stopping event` at 235.4 s, then five
  `GSI command 2 for channel 8 timed out, state 4` (command 2 is
  `GSI_CH_STOP`), `channel 8 global error ee 0x00000000 code 0x00000002`,
  `error -11 attempting to stop endpoint 16`, then `received modem
  offline event`.
- Start: `received modem starting event` at 241.3 s, `received modem
  running event` at 242.7 s.
- ModemManager rebuilt the modem and connected on a new mux
  `qmapmux1.0` (attach 264.0 s, connected 266.2 s) with a new IPv6
  prefix. Gateway ping 0/3, then 0/2 after another 40 s. RX moved
  22 → 28 packets and froze. Pre-restart RX on `qmapmux0.0` was 27.

So the 2026-10-07 claim "only a modem restart restores data" is not
reliable. That day it worked once (35 s) and killed Wi-Fi. Today it
did not restore downlink.

`ipa_table_reset()` and `ipa_mem_zero_modem()` run only inside
`ipa_modem_crashed()`, which the stop notifier calls before the next
start. First boot never runs that path. Today's stop also failed to
stop GSI channel 8, so the reset that follows a clean stop may not
have cleared the wedged RX channel. That is a hypothesis, not a
tested fix.

## Casualties of this one restart

- Sound card was present before the stop (`LG-V30` / `sdm845`). After
  the restart, `/proc/asound/cards` was `no soundcards`.
- ath10k logged `device successfully recovered` at 245.8 s and `wlan0`
  came back `DOWN`/`NO-CARRIER`. Better than the 2026-10-07 MSA leak,
  but there was no saved Wi-Fi profile, so association was not tested.

## Not done

- No third reboot.
- No `ipa.ko` patch. A candidate that resets tables before the first
  `ipa_modem_start`, or that recovers a channel-8 stop timeout, still
  needs two fresh failures of the *candidate* before packaging.
- No DPM open/close. `qmicli` has no read-only DPM query. A fresh WDS
  client reported `disconnected` while ModemManager still held the
  bearer; the proxy path returned `endpoint hangup`.

## Phone left as

pmOS r60, USB gadget up, modem connected, downlink stalled, sound
card absent after the restart. Password file staged for the restart
was removed (`/tmp/joan-pw`, `/tmp/joan-askpass.sh` confirmed absent).
