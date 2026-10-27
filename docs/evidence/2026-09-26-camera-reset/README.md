# 2026-09-26 — camera close/reopen reset: found and fixed

Symptom: with the IMX351 streaming through libcamera, closing the camera and
opening it again within about a second could reset the whole phone. No
oops, no SMMU fault, no kernel message: a silent hang, then the watchdog.
It first showed in raw-capture tests, which is why it looked like a
"raw mode" crash. Raw mode was not the cause.

## What was ruled out

| Suspect | Result |
|---|---|
| Exposure 1 line (garbage frames) | Real driver bug, fixed (minimum now 8, as Rockchip's driver), but the reset still happened |
| Stale VFE write masters (porthole 0106, scratch-page parking) | Imported; reset still happened |
| Missing bandwidth votes for CAMSS | Votes added and verified live in interconnect_summary; reset still happened |
| Refcount leak across sessions | Clock enable/prepare counts, genpd states, regulator use counts identical before and after 20 sessions (`camstate.sh`) |

## The trigger

Scripts in `tools/bench/`: `camvfstress.sh N` (N sessions, 2 s apart),
`camrace.sh N GAP` (N sessions, GAP seconds apart; 0 = back to back),
`protoY.sh IMX CCI` (20 spaced sessions to arm, then set the sensor's
and the CCI's autosuspend delays, then 20 back-to-back).

- Spaced sessions never reset the phone: 40 and then 120 sessions with 2 s
  gaps completed.
- Back-to-back sessions on a freshly booted phone completed twice (6 and
  20 sessions).
- After the pipeline had been through spaced sessions, back-to-back
  sessions reset the phone on every attempt, six of six, within the
  first two sessions in each run whose log shows where.

After arming with 20 spaced sessions, same boot, 20 back-to-back sessions:

| IMX351 autosuspend | CCI autosuspend | Result |
|---|---|---|
| 1000 ms (default) | 0 ms | 20/20 |
| 0 ms | 1000 ms (default) | 20/20 |
| 1000 ms | 1000 ms | reset |

Netconsole breadcrumbs (`netconsole-bl12-last-session.txt`, captured with
tcpdump on nest, no firewall change) place the hang in the second after a
session closes: the last lines are that session's orderly power-down
(`bc: pm put done`), and nothing of the next session reaches the pipeline
power-up. That second is when the sensor's and the CCI's 1 s autosuspend
timers, both armed by the stream-off, fire together, while the next
session is being set up.

## The fix

`media: i2c: imx351: power the sensor down when its stream stops`
(joan/bootlog-fixes 4548026596cc): no autosuspend for the sensor, so it
powers down at stream-off, as LG's stack does. Cost: about 12 ms of
sensor power-up at the next stream start. The CCI keeps its autosuspend
(auto exposure writes the sensor every frame).

Verified on bench kernel bl13: 2 x (20 spaced + 20 back-to-back) sessions,
all 40 back-to-back sessions complete; then 8 rounds of the mixed
raw/viewfinder stress that had reset bl8 and bl9 (32 raw, 8 viewfinder):
all complete, 0 SMMU/timeout messages.

Which hardware access the overlap breaks is still unknown.

## Related fix found on the way

The CCI warned `camss_ahb_clk status stuck at 'on'` on every runtime
suspend: its clock list put camss_ahb last, so it was turned off before
camss_top_ahb and cci_ahb. LG's DT lists it first. With the msm8998 CCI
order changed (binding ffee469280a5, DT d464a5fe2f6d): 0 warnings over
five sessions, previously one per session.
