# joan: the microphone captures on mainline

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-09-11

Supersedes the "silence" conclusion in
`2026-09-10b-capture-silence-isolated-to-slim-tx.md`. The channel-count and
DAPM findings in that note still hold; its "isolated to SLIMbus TX transport"
conclusion does not — SLIMbus TX was fine all along.

## Headline

**Raw microphone capture works on this port.** Verified acoustically, not by
statistics: a 1 kHz tone played from the phone's own loudspeaker appears in the
recording at 1 kHz and disappears when the ADC source is cut.

The blocker was never in the kernel. It is **`pulseaudio` running on the
phone**. Kill it immediately before capturing and the mic records; leave it
running and every sample is zero.

## The evidence

Tone playing continuously from the loudspeaker throughout, `AMIC MUX6` switched
between sources on a fixed `DEC6`/`TX6` chain, 2 s analysis window, Goertzel at
each frequency:

| `AMIC MUX6` | LG name | dBFS | mag @1 kHz | vs 950/1050 Hz |
|---|---|---|---|---|
| ADC1 | handset, bottom | -2.4 | 17392 | 44733x |
| ADC2 | headset, in-line | -74.8 | 0.00 | - (no headset inserted) |
| ADC3 | handset 2nd, top | -32.8 | 522 | 6561x |
| ADC4 | handset 3rd | -66.7 | 10.4 | 1585x |

`pcm0p` was confirmed `state: RUNNING` before **each** of those captures. An
earlier run used a 15 s tone that expired partway through the sweep and made
ADC4 look dead; that result was discarded.

The decisive control, tone playing in both halves:

| condition | RMS | mag @1 kHz |
|---|---|---|
| `AMIC MUX6 = ADC1` | -2.4 dBFS | 17436 |
| `AMIC MUX6 = ZERO` | **exactly 0** | **0.00** |

Cutting the ADC source removes the tone completely, so the signal arrives
through the analog microphone and is not internal RX->TX crosstalk or a DSP
loopback. ADC1 and ADC3 are working microphones. ADC2 is correctly silent with
nothing in the jack. ADC4 registers a real but very faint tone, ~64 dB below
ADC1 — not yet explained, and not claimed as working.

## What `pulseaudio` actually does — and does not do

Reproducible, same boot, same code, three times each:

| pulseaudio | distinct sample values in a 5 s capture |
|---|---|
| running | 2 (all zeros) |
| killed | 249 / 257 / 254 |

**It is not clobbering the mixer.** Every control on the capture chain
(`AIF1_CAP Mixer SLIM TX6`, `CDC_IF TX6 MUX`, `ADC MUX6`, `AMIC MUX6`,
`TX COPP Topology`, `DEC6 Volume`, `ADC1 Volume`) was read back immediately
after setup and again immediately after `arecord`, with PA alive and with PA
dead. **All twelve readings are identical.** The mixer is in the correct state
in the failing case.

Nor does it hold a PCM: with PA running, `/proc/asound/card0/pcm0p/sub0/status`
and `pcm1c` both read `closed`, and the only `/dev/snd` descriptor PA holds is
`controlC0`.

So the mechanism is still unknown. What is established is that it is *not*
control state and *not* a PCM open. Suspect a concurrent ADSP-side session
(ASM/ADM) or card-level state held through `controlC0`.

`pulseaudio` here is **autospawned**, not a service — there is no
`pulseaudio.service` on this image, and it reappears within a second of being
killed. `pacmd suspend true` is *not* equivalent: it frees the playback PCM but
capture still records zeros. Only killing it works.

### Working recipe

    # tone/playback first, so aplay owns pcm0p before PA respawns and steals it
    aplay -D hw:0,0 /tmp/tone60.wav &
    sleep 2
    killall -9 pulseaudio            # <- the actual unblock
    sleep 1
    # clear the whole capture mixer family, then enable exactly one port
    amixer -c0 contents | grep -o "name='AIF[0-9]_CAP Mixer SLIM TX[0-9]*'" \
      | sed "s/name='//;s/'$//" \
      | while IFS= read -r n; do amixer -c0 cset name="$n" 0 >/dev/null; done
    amixer -c0 cset name='AIF1_CAP Mixer SLIM TX6' 1
    amixer -c0 cset name='CDC_IF TX6 MUX' DEC6
    amixer -c0 cset name='ADC MUX6' AMIC
    amixer -c0 cset name='AMIC MUX6' ADC1
    amixer -c0 cset name='TX COPP Topology' None
    arecord -D hw:0,1 -f S16_LE -r 48000 -c 1 -d 5 /tmp/mic.wav

Ordering matters twice over: the playback must be started before PA is killed
(otherwise the respawn takes `pcm0p` and `aplay` returns `Resource busy`), and
`TX COPP Topology` must be set after any `alsaucm _enadev`.

## Why the previous note concluded "transport"

Every capture it measured was taken with `pulseaudio` running, so every one was
zero, and the inference from that — "exact zeros over 288000 samples cannot be
a quiet mic, so no data is arriving" — was sound reasoning from a sample set
that had one uncontrolled variable in it. The bench had been up 4-8 h with the
phosh session live the entire time. The hypothesis was never wrong about the
data; it was wrong about the cause, because the daemon was never in the
experiment design.

Retained from that note, still true: the channel-count rule (clear every
`AIF*_CAP Mixer SLIM TX*` first, or the ADSP rejects the AFE port), and the
correction that `out 0` on a `dai_out` widget means "no active stream", not
"unrouted".

## Next

- Explain ADC4 (-66.7 dBFS): micbias, the `AMIC4_5 SEL Mux`, or simply not
  populated. `mictest-allmic` in the stock XML exercises ADC1-ADC4 together.
- Test ADC2 with a headset actually inserted.
- **Wire the capture path for PipeWire + WirePlumber, not PulseAudio**
  (Lance, 2026-09-11 — this is the durable fix, do it before anything else in
  this list). Telling everyone to `killall pulseaudio` is a bench hack, not a
  port. What the image actually has today:

      pulseaudio                    running, autospawned, no .service unit
      pipewire.service              loaded, inactive, dead
      wireplumber.service           loaded, inactive, dead
      pipewire.socket               loaded, active, listening
      pipewire-pulse.service        not-found
      call-audio-idle-suspend-workaround.service   running (polls PA, respawns it)

  So the session is on legacy PulseAudio while the PipeWire units sit unused.
  The work: bring up `pipewire` + `wireplumber`, add `pipewire-pulse` for the
  PA shim, make sure PulseAudio cannot autospawn alongside them, and confirm the
  UCM capture devices (`Mic`, `Headset`, `DualMic` on `hw:x,1`, added
  2026-09-07) surface as WirePlumber sources with the right `AIF*_CAP` /
  `TX COPP Topology` sequence. `pipewire-echo-cancel` is already in the device
  package depends, so the WebRTC NS/AEC layer lands on top of this.
- Find the real PA interference mechanism — worth knowing even once the stack
  moves to PipeWire, because whatever it is may bite WirePlumber too.
- Wire the verified sequence into `scripts/bench-automation/`.

## Bench state

Phone up on the RAM-booted pmOS, nothing written to the SD card. Runtime-only,
all reverted by a reboot: `joan_pipes=Y`,
`call-audio-idle-suspend-workaround.service` stopped, pulseaudio repeatedly
killed (it respawns), capture mixer left on TX6/ADC1, `TX COPP Topology` None.
Recordings and the tone files are in
`~/.ember/workspace/joan-audio-2026-09-10/`.
