# joan — loudspeaker fixed, SLIMbus playback working (2026-08-22)

Signed-off-by: Lance <Gero3977@gmail.com>
Assisted-by: Claude-Code:claude-opus-5
Date: 2026-08-22

## Headline

Two results, both confirmed by ear on hardware:

1. **The loudspeaker plays.** The TFA9872 was never being enabled: mainline
   `tfa989x` addresses it with the older TFA1 register map, and this part uses a
   different one. Fixed in `linux-lg-v30-joan` `725ca5cc8`.
2. **SLIMbus playback works.** Audio reaches the WCD9340 and comes out of
   HPHL/HPHR to the headphone jack. This supersedes the conclusion in
   `aurel-handoff-2026-08-18-audio.md` (see "What changed" below).

Still open: the earpiece is silent, and that is now a *board-level* question,
not a bus or codec one.

## 1. TFA9872 — the register map is different

The part is one of NXP's **Probus** devices: it has no CoolFlux DSP at all. Its
register map contains none of the DSP interface fields (`CFE`, `SBSL`, `ACS`,
`DMEM`, `MADD`, `MEMA`, `RST`) — the TFA9912 map has all nine, the TFA9872 map
has zero. So there is nothing to "bypass", and nothing to wire up.

What mainline had wrong, and where the fields actually live:

| field | real address | `tfa989x` used |
|---|---|---|
| `PWDN` / `AMPE` / `DCA` | reg `0x00` bits 0/3/4 | reg `0x09` — not implemented |
| `I2CR` (I2C reset) | reg `0x00` bit 1 | reg `0x09` — so the part was never reset |
| `AUDFS` sample rate | reg `0x02` bits **3:0** | reg `0x04` bits 15:12 |
| status (`PLLS`/`CLKS`/`SWS`/`AMPS`) | reg **`0x10`** | reg `0x00` |

Writes to the unimplemented offsets are accepted on the wire and silently
dropped, so DAPM reported the amplifier powered and enabled while the chip sat
at its power-on default with `PWDN` set.

Two more things were needed:

- `TDMSLLN` (reg `0x21` bits 8:4) resets to **32 bits per slot**, which cannot
  fit two slots into the 32-BCK frame sent for S16_LE stereo. Left alone the
  part raises `TDMERR` and drops out of operating state ~80 ms after starting.
- The amplifier is **not** enabled by writing `AMPE`. An on-chip manager engages
  it once `MANSCONF` (reg `0x01` bit 2) signals the host has finished
  configuring. Setting `AMPE` first makes the manager clear it and refuse to
  leave its wait state.

Working bring-up order: `I2CR` → two-key unlock → vendor init table → `PWDN=0`
→ `MANSCONF=1`. The manager brings up `AREFS` at ~2 ms, `CLKS`+`AMPS` at ~4 ms,
`SWS` at ~5 ms.

### Instruments that paid off

- **Status register `0x10`**, read while playing. `PLLS`/`CLKS`/`SWS`/`AMPS`
  tell you exactly how far the manager got. Reading `0x00` (which is a *control*
  register on this part) tells you nothing.
- **Tight polling after `MANSCONF`.** The failure was a transient: fully up at
  5 ms, collapsed at 85 ms. A one-second poll interval sees only the corpse.
- Prototype scripts kept in `out/tfa9872-bringup/`.

## 2. SLIMbus playback — what changed

`aurel-handoff-2026-08-18-audio.md` records that sound does not play over
SLIMbus and that a silent SoC reset kills the stream 0.3–1.3 s after the AFE
port config. **Neither is true on the current kernel.** Measured 2026-08-22:

- No SoC reset across a dozen streams; uptime continuous throughout.
- The stream configures (`slim port 16384 cfg: ch 2 ... map 144/145`), runs its
  full duration, and tears down cleanly with no DSP or AFE errors.
- HPHL/HPHR output is **audible at the headphone jack**.

That handoff's analysis was correct for its kernel; the PGD write removal
(`f173f0394`) and the intervening work appear to have closed it. Its remaining
leads (SPS/BAM port, codec PGD interrupt enables) are no longer blocking
playback.

### The traps that cost the most time here

- **Userspace owns the card.** `pipewire`, `wireplumber` and `pulseaudio` run
  under phosh and claim SLIM RX0 via the UCM profile. `slim_rx_mux_put()` then
  logs `SLIM_RXn PORT is busy` and **returns 0 without updating the value**, so
  the control silently reads back 0. Worse, the state cannot be cleared from
  userspace afterwards (the `case 0` path bails when the previous index is 0) —
  it needs a reboot. Kill the daemons *before* configuring.
- **numids are not stable across kernels.** Removing the `Amp Input` mux from
  the TFA9872 DAPM deleted kcontrols and shifted every numid after it. Always
  resolve controls by name; a hardcoded numid silently configures a *different*
  control (this had us setting `SLIM RX2 MUX` while believing it was RX0).
- `slim_stream_prepare()` / `slim_stream_enable()` had their return values
  discarded in `wcd934x_trigger()`, so bus failures were invisible. Fixed in
  `c2a302cea`.

## 3. Earpiece — open, and narrowed

The vendor's own `mixer_paths_tavil.xml` (`/vendor/etc/`, readable by mounting
the Android `system` partition read-only) gives the exact handset path:

```
SLIM RX0 MUX = AIF1_PB ; CDC_IF RX0 MUX = SLIM RX0 ; SLIM_0_RX Channels = One
RX INT0_1 MIX1 INP0 = RX0 ; RX INT0 DEM MUX = CLSH_DSM_OUT ; EAR PA Gain = G_6_DB
```

With that applied (minus `CDC_IF RX0 MUX`, which mainline wires statically):

- `ANA_EAR` (0x60a) reads `0x80` — the EAR PA **is** enabled in hardware.
- The whole DAPM chain powers: `SLIM RX0` → `RX INT0_1 MIX1` → `RX INT0 MIX2` →
  `RX INT0 DEM MUX` → `RX INT0 DAC` → `EAR PA` → `EAR`.
- Class-H is configured for EAR by mainline (`WCD_CLSH_STATE_EAR` on PRE_PMU).
- The stream is error-free.
- **And it is silent**, while HPHL/HPHR on the same codec, bus and stream are
  audible.

So the codec, SLIMbus and DSP are all exonerated. What remains is the EAR pin
itself or what it drives on this board. Note `RX INT0 DEM MUX` must be
`CLSH_DSM_OUT`: `NORMAL_DSM_OUT` has no route defined at all in
`wcd934x.c:5649` and silently breaks the chain.

Board-level things not yet checked: the `hph-sw` analog switch
(`pm8998_gpios 12`, held low by `es9218p`, never changed) and whether any other
switch gates the receiver.

## Rig notes (additions)

- `/tmp` on the phone is tmpfs: helper scripts do not survive a reboot.
- Restarting the ADSP (`remoteproc1` stop/start) is enough to re-run first-time
  stream setup — cheaper than a reboot when chasing one-shot events.
- `dmesg -c` destroys the boot log you may need. The `apr.apr_hb_ms=10`
  heartbeat wraps an 8 MB buffer in ~20 minutes, so boot messages are gone after
  a few hours anyway; capture early rather than clearing.
- `slim_qcom_ngd_ctrl.pgd_enable` must stay **0** — the driver documents it as
  "DANGEROUS: hangs the controller on current mainline".
- `joan_pipes` defaults to **on** and should stay on; the debug cmdline had it
  disabled.
