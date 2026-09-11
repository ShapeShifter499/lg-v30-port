# joan: the ES9218P mode control, and what blocks Low Power Bypass

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-09-11

Follows `2026-09-11-pipewire-cutover-and-audio-stack.md`, which established that
`hph_switch` is the ES9218P's MODE2 pin rather than a board-level analogue
switch, and concluded that low-power audio needs a driver change before any UCM
work can matter. This is that driver change, and the wall it hит.

## 1. Confirmed by ear: the buffer fix is the real result

With the measured parameters in place (playback `period 6240 x 4`,
`disable-tsched`, `disable-mmap`), Lance on the ES9218P HiFi path:

> "I hear a clear tone, no wobble"

That closes out the waver, crackle and dropouts that dominated the session. The
values came from reading `hw_params` off a working `aplay`/`arecord`, not from
upstream, not from Android's HAL, and not from guesswork — all three of which
were wrong in both period size and count.

## 2. `Headphone Mode`

`Headphone Analog Switch` (a bool that drove one pin, and was described in our
own source as "the board's analog jack switch ... while the destination of each
analog output is still being mapped") is replaced by a four-state enum that
drives RESET_N and MODE2 together, because they are one two-bit mode field:

| mode | reset (gpiod) | mode2 | meaning |
|---|---|---|---|
| HiFi | 0 | 0 | DAC + amplifier active |
| LowFi | 0 | 1 | |
| Low Power Bypass | 1 | 1 | DAC down, analogue passed through |
| Standby | 1 | 0 | shutdown |

`reset-gpios` is `GPIO_ACTIVE_LOW` in DT, so a gpiod value of 0 means RESET_N is
*high* and the part is out of reset. `hph-sw-gpios` is ACTIVE_HIGH and maps
straight through. Note what this means for the old control: with reset held at
0, toggling `hph_sw` only ever moved between **HiFi and LowFi** — it never
reached LPB, which is why the earlier "flip the switch" experiments produced a
click and silence in both positions.

Leaving an amplifier mode also needs a register handoff, transcribed from
downstream `es9218p_sabre_hifione2lpb()`: write `AMP_CONFIG = 0` ("amp mode core
on, amp mode gpio set to trigger Core On", which leaves the part in LowFi under
GPIO2 control), wait, then pull RESETb low. The 100 ms settle is what LG
compiles in for this board specifically (`CONFIG_MACH_MSM8998_JOAN`); the
generic path has none.

The control is built, deployed and working:

    numid=98,iface=MIXER,name='Headphone Mode'
      ; type=ENUMERATED,items=4
      ; Item #0 'HiFi'  #1 'LowFi'  #2 'Low Power Bypass'  #3 'Standby'

## 3. What blocks the experiment

    es9218p 0-0048: ASoC error (-6): at snd_soc_dai_hw_params() on es9218p-hifi
     Quaternary MI2S Playback: ASoC error (-6): at __soc_pcm_hw_params()
     MultiMedia1: ASoC error (-6): at dpcm_fe_dai_hw_params() on MultiMedia1

`-6` is `ENXIO`: the ES9218P cannot be configured over I2C while held in reset,
which is correct behaviour. The defect is that **the ES9218P backend stays
attached to MultiMedia1 even with `QUAT_MI2S_RX Audio Mixer MultiMedia1` off**
(verified: the mixer reads `off` and the backend is still in the path). Our
driver never powers its DAPM widgets down — `DAC | HPOUTL | HPOUTR | Playback`
were observed on continuously for the whole session — so the backend never
detaches, and the front-end open dies on it the moment the chip leaves HiFi.

So Low Power Bypass cannot currently be exercised through MultiMedia1 at all,
and the question the whole low-power plan rests on — does LPB route the WCD's
analogue through to the jack — **is still unanswered**.

## 4. A second defect in the same control, found the hard way

Going into LPB pulls RESET_N low, which clears the part's registers. Coming back
to HiFi, `es9218p_mode_put()` restores only the pins: it does not re-run
`es9218p_init_seq` or `es9218p_amp_power_up()`, which execute at probe. The
result is a path that looks entirely healthy — mode reads HiFi, the route is up,
`pcm0p` reports `RUNNING` — and is silent.

This was mistaken for a failed test before Lance reported hearing nothing on a
run that every instrument said was fine. Instruments agreeing is not the same as
the thing working, and a human listener caught what none of the readbacks did.

## 5. Two corrections to the record

* **The reboot was not necessary.** PCM opens were failing with `EINVAL` because
  no backend was routed — a DPCM front-end cannot open without at least one BE,
  and earlier in the session the mixers happened to be left on from prior
  commands. This was diagnosed as the module reload having corrupted the card,
  and a reboot was requested on that basis. Enabling any BE mixer fixes it:

      amixer -D hw:0 cset name='QUAT_MI2S_RX Audio Mixer MultiMedia1' 1

* **Renaming a control means updating the UCM that names it.** `HiFi.conf` still
  carried `cset "name='Headphone Analog Switch' on"`, so the whole device enable
  aborted (`[error.ucm] unable to execute cset`) and nothing routed. Fixed to
  `cset "name='Headphone Mode' Low Power Bypass"` / `HiFi`.

## 6. Build and deploy mechanics worth keeping

Rebuilding one in-tree module against a running kernel needed three things that
each cost a cycle:

* **vermagic.** A dirty worktree makes `CONFIG_LOCALVERSION_AUTO=y` stamp
  `-dirty`, which the running kernel rejects. `.scmversion` does not suppress
  it. Pin `CONFIG_LOCALVERSION="-g<hash>"`, unset `CONFIG_LOCALVERSION_AUTO`,
  and pass `LOCALVERSION=` explicitly or you get a trailing `+`. Restore
  `.config` afterwards — ours is back byte-identical.
* **`make <path>/<module>.ko` truncates `modules.order` to one line**, after
  which every later `make modules` runs modpost against a module set of one and
  reports the core ASoC exports as undefined. Delete `modules.order` and
  `Module.symvers` to recover.
* **Strip it.** The staged module set is stripped; an unstripped 505 KB module
  against the original's 18 KB would not load even with `modprobe --force`.

## 7. Next

Both fixes are in `es9218p.c` and belong together:

1. Re-run `es9218p_init_seq` and `es9218p_amp_power_up()` on the transition back
   into HiFi, instead of only restoring the pins.
2. Gate the ES9218P DAPM path so the backend detaches when the part is not in
   HiFi — without this, LPB cannot be tested at all.

Then the original question can finally be asked: enable the `Headphones` UCM
device, put the part in Low Power Bypass, and find out whether the jack carries
the WCD9340's HPHL/HPHR.

## Bench state

Phone on the RAM-booted pmOS (rebooted and re-staged this session; module tree
is tmpfs and does not survive a reboot). Card registered, `Headphone Mode` = HiFi,
QUAT route enabled. **Headphone output is currently silent** because of §4 — the
part has been through LPB and not re-initialised, and a codec reload was refused
("module in use"). A reboot clears it; nothing persistent is damaged.
