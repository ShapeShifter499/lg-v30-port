# Handoff: LG V30 (joan) audio capture — Ember to Fulgor

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-09-07

Welcome aboard. This is the state of joan's audio capture work. Everything
below is **committed, and none of it has been booted.** Your first job is to
find out how much of it is true.

## The one thing to read first

`docs/2026-09-07-mic-routing-from-downstream.md`. It has the full mic map, the
MBHC values, the ADSP topology findings, and — importantly — the two places
where I stated something too strongly and had to correct myself. Read the
corrections; they mark where the evidence is thin.

## Where the code is

| repo | branch | state |
|---|---|---|
| `linux-lg-v30-joan` | `joan/latest-clean-test` **and** `joan/mbhc-headset-mic-v2` | pushed, both at `fb968169503b` |
| `pmaports-lge-joan` (local `pmaports-lg-v30-clean`) | `joan/readme-build-guide` | **committed, NOT pushed** |
| `lg-v30-port` | `ember/pmaports-joan-gpu-publish-handoff` | committed, not pushed |

The kernel push was a clean fast-forward from the old pin `1b42626b`, so all
history is intact. pmaports still pins `1b42626b` and carries the two new
commits as patches — `0002-joan-micbias-mbhc-amic4.patch` and
`0003-q6routing-selectable-tx-topology.patch`. Both verified to apply in
sequence against the pin. If you re-pin pmaports to `fb968169503b`, **drop
those two patches** or the build will fail on already-applied hunks.

## What to test, in this order

Order matters. Later steps can mask earlier failures.

### 1. Raw capture, before anything clever

```
amixer -c0 cset name='TX COPP Topology' None      # neutralise step 3 first
alsaucm -c 0 set _verb HiFi set _enadev Mic
arecord -D hw:0,1 -f S16_LE -r 48000 -c 1 -d 5 /tmp/mic.wav
```

Repeat for `Headset` (1ch) and `DualMic` (2ch). If these do not work, nothing
else in this handoff matters.

### 2. MBHC — the headset switch and in-line buttons

Plug a 4-pole headset with a 3-button remote.

```
cat /proc/asound/card0/... ; evtest    # look for the jack input device
```

Expect insert/remove events, and the three buttons to decode as
`KEY_PLAYPAUSE`, `KEY_VOICECOMMAND`, `KEY_VOLUMEUP`/`KEY_VOLUMEDOWN` —
distinctly, not all as PLAYPAUSE. **All-PLAYPAUSE means the button threshold
ladder did not take.**

The live jack IRQ has been dead for a long time and was noted as such before I
touched it. I found that `gnd_swh` was left at mainline's default `true` while
stock says `0` (normally closed), which writes the wrong value into
`WCD_MBHC_GND_PLUG_TYPE`. That is a *plausible* cause, not a proven one. If the
IRQ is still dead after this, that hypothesis is spent — do not keep spending
time on it, look at the interrupt plumbing instead.

### 3. ADSP noise suppression — the risky one

```
amixer -c0 cset name='TX COPP Topology' DM_Fluence
```

**This can fail closed.** If the ADSP rejects the topology, the COPP open fails
and the input goes *silent*, not merely unprocessed. That is a different
failure mode from "NS didn't work" and it is easy to misread. Recovery is
always:

```
amixer -c0 cset name='TX COPP Topology' None
```

The UCM devices already set this per LG's own calibration (`SM_ECNS` for a
single mic, `DM_Fluence` for the pair), so if a mic is silent in step 1, try
`None` before concluding the routing is wrong.

## Physical buttons: already wired, nothing to do

* Volume up — `pm8998_gpios 6`, `KEY_VOLUMEUP`, wakeup-source
* Volume down — `&pm8998_resin`, `KEY_VOLUMEDOWN`
* Power — `&pm8998_pwrkey`, with `qcom,pon-dbc-delay` raised to the vendor's
  31250 because joan's power switch chatters (a real measured fix, don't revert
  it)

That is the complete V30 button set; there is no assistant key. The in-line
headset buttons are the MBHC path in step 2, not GPIO keys.

## Things I believe but have not proven

Treat these as leads, not facts.

* **DMIC.** I first claimed joan has no digital mics, then found the camcorder
  paths select `DMIC0` and the stock DTB sets
  `qcom,cdc-dmic-sample-rate = <4800000>`. The factory all-mic test uses only
  analog inputs, and both DMIC signals also appear in Qualcomm's generic 8998
  config, which is the likelier read. **Unresolved.** If you ever get capture
  on a DMIC route, that settles it.
* **Micbias at 2750 mV.** Taken from the stock DTB. Verify by register readback,
  not by echoing the control back — an ALSA control read tells you what you
  wrote, not what the codec did.
* **Camcorder orientation.** `Camcorder` / `CamcorderRotated` UCM devices carry
  LG's three-mic routing with the ADC1<->ADC3 swap. Nothing selects between
  them; that is userspace policy keyed to rotation, and joan has no working
  camera. Routing only.

## Deliberately not done

* **ACDB blobs are not packaged.** They are inert without
  `ADM_CMD_SET_PP_PARAMS_V5` in `q6adm` (mainline implements only
  `DEVICE_OPEN_V5`, `DEVICE_CLOSE_V5`, `MATRIX_MAP_ROUTINGS_V5`) plus a parser
  for the format. ACDB is **per-model** — `Handset_cal.acdb` is 674039 bytes on
  US998 and 670571 on H932 — so it would need per-device packaging, unlike the
  Bluetooth firmware which is byte-identical between the two.
* **`"MIC BIAS2", "Headset Mic"` route.** Stock has it, but `sdm845.c`
  pin-switches that widget from jack state. While jack detect is unreliable, a
  "no jack" report would pull MIC BIAS2 down and silence headset capture.
  Revisit once step 2 passes.

## House rules you will be held to

* Commit trailers: `Signed-off-by: Lance <Gero3977@gmail.com>` and
  `Assisted-by: Claude-Code:<the model actually running>`. **Never**
  `Co-Authored-By: Claude`.
* Stage, do not push, unless Lance says so. The kernel push above was
  explicitly authorised.
* Never delete anything without per-item approval.
* Confirm external-publish actions before taking them.

## Open, beyond audio

IPA near-null IOVA `0x38` read on real uplink is still unexplained — see
`docs/2026-08-23-cellular-data-gsi-uplink.md`. Do not point IPA DMA at a guessed
address; I did that and put the phone into download mode, wiping the system.
