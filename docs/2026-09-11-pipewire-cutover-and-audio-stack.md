# joan: PipeWire cutover, the capture fix, and the ES9218P mode pins

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-09-11

Follows `2026-09-11-microphone-capture-works.md`. That note ended with "wire the
capture path for PipeWire and WirePlumber, not PulseAudio" as the next task.
This is that work, plus what it turned up underneath.

## Headline

PulseAudio is gone and the stack runs on PipeWire + WirePlumber + pipewire-pulse.
Capture works through it. Playback runs at real time with zero errors once the
ALSA buffer parameters are set to values **measured from this device** rather
than copied from upstream or from Android.

Two real defects were fixed, one long-standing misconception was corrected, and
one new hardware fact was established that changes the plan for low-power audio.

## 1. The cutover

    apk add postmarketos-base-ui-audio-backend-pipewire \
            pipewire-pulse pipewire-alsa pipewire-echo-cancel

Purged: `pulseaudio`, `-alsa`, `-bluez`, `-lang`, `-wireplumber`,
`postmarketos-base-ui-audio-backend-pulseaudio`, `webrtc-audio-processing-1`.
Installed alongside the above: `pipewire-pulse-systemd`, `pipewire-tools`,
`pipewire-spa-bluez`, `bluez-libs`, `liblc3`.

`postmarketos-ui-phosh` is **not** removed — the metapackage satisfies the same
dependency, which is what made this possible. A plain `apk del pulseaudio` is
refused because phosh depends on it; the backend metapackage is the supported
swap. `/usr/bin/pulseaudio` is gone; the name now resolves to `pipewire-pulse`
as a provider, so `apk info -e pulseaudio` still succeeds and is not proof the
daemon is installed.

The phone has no default route. Package access was given by running a ~40-line
Python HTTP forward proxy on the nest bound to the USB link only
(`172.16.42.2:3128`) and exporting `http_proxy` for apk. No routing or firewall
change on the gateway, nothing to undo but killing the process.

## 2. PipeWire could never have started on this image

    pipewire[10085]: could not load mandatory module
                     "libpipewire-module-echo-cancel": No such file or directory
    pipewire.service: Failed with result 'start-limit-hit'

`/usr/share/pipewire/pipewire.conf.d/50-joan-echo-cancel.conf` — owned by no
package, so hand-placed in an earlier session — declares the echo-cancel module
**mandatory**, while `pipewire-echo-cancel` was never installed. pipewire exited
254 in a restart loop and wireplumber died on the dependency. That is why the
system was still on PulseAudio at all.

Fixed by marking the module `flags = [ ifexists nofail ]`, so the drop-in is
inert until the package is present. The package is now installed and the filter
loads.

## 3. The real cause of the "pulseaudio blocker"

The previous note recorded that killing `pulseaudio` made capture work and that
the mechanism was unknown. The mechanism is our own UCM.

Every capture device's `EnableSequence` in `HiFi.conf` set
`TX COPP Topology SM_ECNS`, which fails the ALSA capture open outright:

    spa.alsa: '_ucm0008.hw:LGV30,1': capture open failed: Invalid argument
    arecord: set_params:1462: Unable to install hw params

Killing PulseAudio "fixed" capture only because it stopped anything from
*running* that sequence, leaving a manually-set `None` in place. PipeWire
reproduced the failure exactly. Patched to `None` throughout; capture then
works with the sound server running, no daemon-killing.

Note the failure is self-sustaining: with the topology stuck at SM_ECNS the
capture open fails, so WirePlumber drops the card profile to `off`, so the
patched EnableSequence never runs to set it back. Clearing the control once by
hand breaks the loop.

## 4. Buffer parameters, measured rather than assumed

`pw-play` took **170 s to play a 45 s file** and exited 1. The sink played its
first buffer and then stalled while the PCM still reported `RUNNING`.

The answer came from reading `/proc/asound/card0/pcm*/sub0/hw_params` while
plain `aplay`/`arecord` ran successfully on the same device:

| | period | periods | buffer | result |
|---|---|---|---|---|
| `aplay` (works) | 6240 | 4 | 24960 | 5.0 s file in 5.7 s |
| `arecord` (works) | 1920 | 8 | 15360 | records |
| my guess | 960 | 8 | 7680 | stalls |
| pmaports `51-qcom.conf` | 4096 | 6 | — | glitches |
| Android HAL deep buffer | 1920 | 2 | — | chopped, underruns |

With 6240x4 / 1920x8 applied: **45 s file plays in 46.0 s (1.022x), zero
errors**.

Three things worth carrying forward:

- **`q6asm-dai.c` caps capture periods at 4096 _bytes_** (`CAPTURE_MAX_PERIOD_SIZE`),
  i.e. 2048 frames mono — so pmaports' shared `api.alsa.period-size = 4096`
  *frames* is illegal on this driver. Worth reporting upstream.
- **Android's HAL numbers do not transfer.** tinyALSA writes exactly one period
  from a dedicated thread and sets `stop_threshold = INT_MAX` so ALSA never
  halts on underrun; PipeWire uses `stop_threshold = buffer_size`, so the first
  underrun leaves the PCM stuck in `XRUN`. That is the architectural reason
  LineageOS sounds fine on hardware we are fighting, and PipeWire exposes no
  knob for it.
- **q6asm already declares `SNDRV_PCM_INFO_BATCH`** — the driver is honest about
  its coarse pointer. It still needs `api.alsa.disable-tsched`; PipeWire's batch
  handling alone was not sufficient here (tested, and worse without it).

Also needed: `api.alsa.disable-mmap`. Under mmap the capture PCM returned
`snd_pcm_mmap_commit error ... Broken pipe` continuously and sat permanently in
`XRUN`, which disturbed playback through the shared graph.

## 5. The capture node was driving the graph

    "node.driver-id": 107
    107 = alsa_input...Mic__source     priority.driver 1728   <- driving
    104 = alsa_output...Headphones__sink priority.driver 1000 <- follower

Playback was being adaptively resampled onto the ADSP **capture** clock, whose
estimate wanders — audible as a wavering pitch on a sustained tone. The
echo-cancel filter pins the mic as always-processing, which is how it won the
election. Fixed in `53-joan-driver-priority.conf` (output 2000, input 900).

## 6. The ES9218P mode pins — this changes the low-power plan

The goal was a "normal vs hi-fi" toggle: idle on the WCD9340's own HPHL/HPHR
amplifiers and engage the ES9218P Quad DAC only on demand, since LG explicitly
calls the alternative "Low Power Bypass".

**That premise was wrong, and the correction is the useful part.** From LG's
downstream `es9218p.c`:

     * reset_gpio;         //HIFI_RESET_N
     * hph_switch_gpio;    //HIFI_MODE2
     *   reset=H && mode2=L  --> HiFi mode
     *   reset=L && mode2=H  --> Low Power Bypass mode
     *   reset=L && mode2=L  --> Standby (Shutdown)
     *   reset=H && mode2=H  --> LowFi mode

`hph_switch` is **not a board-level analog switch between the WCD and the
ES9218P**. It is the ES9218P's MODE2 pin; with RESET it forms a 2-bit mode
field on the DAC itself. "Low Power Bypass" is a mode of the ES9218P in which
it bypasses its own DAC and passes analog through to the jack.

Our driver holds `reset = H`, so toggling `hph_sw` alone only moves between
HiFi (L) and LowFi (H) and never reaches LPB. Measured on hardware: with the
WCD HPHL/HPHR chain fully powered and two channels verifiably on the bus, the
jack produced a click (the PA enabling) and then silence, in **both** switch
positions.

Our own `es9218p.c` calls the control "the board's analog jack switch", with a
comment conceding "the destination of each analog output is still being
mapped". That guess is what the plan was built on.

LG also selects among HiFi modes by **headphone impedance**, measured on
insertion while idling in LPB:

    <=50 ohm        -> HiFi1
    >50 - <600 ohm  -> HiFi2   (asserts SEL3V3/SEL3V3_PS and ENSMPS: the 3.3 V
                                rail in "strong" mode, the most power of the three)
    >600 ohm        -> HiFi1   (line-out)

### What this means for the work order

Low-power audio **cannot** be done from UCM. The order is the reverse of what
was assumed:

1. Drive both GPIOs as one 2-bit mode field and rename the control accordingly
   (`Headphone Mode`: HiFi / LowFi / LPB / Standby), not `Headphone Analog Switch`.
2. Implement `es9218p_sabre_hifi2lpb()` / `lpb2hifione()` / `lpb2hifitwo()` and
   `standby2lpb()` from LG's sequences.
3. Only then does a low-power UCM device become audible.

Impedance-based auto-selection additionally needs jack/impedance detection,
which is blocked on the same MBHC gap as the in-line mic.

## 7. UCM: the headphone split (landed, not yet audible)

`HiFi.conf` now has both, and the routing half is verified:

- `Headphones` — WCD9340 HPHL/HPHR, priority 200. SLIMBUS_0_RX -> SLIM RX0/RX1
  -> RX INT1/INT2 -> HPHL/HPHR. Stock reaches these over `AIF4_PB` on
  SLIMBUS_6_RX, which our DTS does not wire (only `SLIMBUS_0_RX <-> wcd9340 0`
  and `SLIMBUS_0_TX <-> wcd9340 1`), so it uses the link we have.
- `HeadphonesHiFi` — the existing QUAT_MI2S -> ES9218P path, priority 100.

Confirmed on hardware: both appear as separate WirePlumber profiles, `HPHL`,
`HPHL PA`, `HPHR`, `HPHR PA` and the full RX INT1/INT2 chains power up, and the
bus carries two channels (`slim-rx port=16 ch=144`, `port=17 ch=145`,
`slim port 16384 cfg: ch 2 map 144/145`). It is silent only for the reason in
§6, so the device is left in place.

## 8. Jack detection is still not working

With headphones physically inserted:

    numid=99  'Headphone Jack'    : values=off
    numid=100 'Headset Mic Jack'  : values=off
    all card profiles:  "available": "unknown"

The `LG-V30 Headset Jack` input device exists (event4) but MBHC reports nothing.
PipeWire's choice of a Headphones profile is priority-based, not detection.
The micbias/ground-switch DTS fixes on `joan/mbhc-headset-mic-v2` have still
never been booted, and this kernel predates them. The `Headset` capture node
also fails to create (`Failed to create ALSA node ...HiFi__Headset__source`),
so ADC2 remains untested.

## 9. Repo map correction

**The live UCM source is
`pmaports-lg-v30-clean/device/testing/alsa-ucm-conf-lge-joan/HiFi.conf`**
(9 devices, 5 capture). The copy in `lg-v30-joan-pmos-packages/` is **stale**
(3-4 devices, no capture devices at all), and `alsa-ucm-conf-lge-joan/` has 1.

Deploying the stale copy to the phone removed every microphone device. It was
restored from a backup taken in the same command, but this is a trap worth
naming: `joan-repo-map` says packages live in `lg-v30-joan-pmos-packages`, and
for this file that is wrong.

## Bench state

Phone up on the RAM-booted pmOS, ~13 h uptime, nothing written to the SD card
except the audio configuration changes listed here. Live config:

    /usr/share/alsa/ucm2/Qualcomm/sdm845-lge-joan/HiFi.conf   (+Headphones split,
                                            topology None; .before-hph-split kept)
    /etc/wireplumber/wireplumber.conf.d/53-joan-driver-priority.conf
    /etc/wireplumber/wireplumber.conf.d/54-joan-no-mmap.conf   (measured buffers)
    /usr/share/pipewire/pipewire.conf.d/50-joan-echo-cancel.conf.disabled

Backups kept beside each edited file. The echo-cancel drop-in is disabled
because its capture side held the mic PCM open permanently in XRUN; re-enable
it once the buffer settings are confirmed stable.

## Process notes, for the next session's benefit

- **Run session tools as `user`, never under `sudo`.** `wpctl`, `pw-cli` and
  `systemctl --user` need `XDG_RUNTIME_DIR`/the session bus; under `sudo` they
  silently address an empty session and report "no sink" and blank profiles.
  Several hours were spent believing the graph was fragile when the harness was
  simply asking the wrong session. Split scripts: user for the session, root
  only for regmap/debugfs.
- **`pkill -f <pattern>` matches the ssh command line** that carries it and will
  kill its own session (exit 255). Same self-match trap as `pgrep -f`.
- **Do not tune by ear across multiple variables.** One `hw_params` read from a
  working `aplay` pointed straight at the answer that hours of listening tests
  did not. Change one variable, and prefer a measurement the device can give you
  over a human's report where one exists.
