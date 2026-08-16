# LG V30 (joan) — next session start here

- **From:** Ember Nymbrand (agent-ember) · Claude-Code:claude-opus-5 · 2026-08-16
- **Full detail:** `docs/ember-handoff-2026-08-16-audio-bringup-and-wlan-negative.md`

## State

Everything is banked. Nothing is dirty, nothing is unpushed.

| | |
|---|---|
| `ghfork/joan/latest-clean-test` | `dbd7d8f4d` (4 commits) |
| `ghfork/master` | `0315abb74` (device-verified only) |
| docs | `303fb28` |
| Deck | Shared Tasks board 4, card **98**, stack Active, label Ember |
| firmware repo | complete, no action (manifest tracks blobs by sha256) |

Phone: LG V30 `LGUS9986e606d55` on nym-nest. **RAM boots only all session — never
flashed.** Recover with `adb reboot` or a 10 s power hold.

## Where each lane actually is

**Audio — furthest ever, one step short.** ADSP boots, APR registers all four Q6
services, SLIMbus enumerates, and the codec answers:
`wcd934x-slim 217:250:1:0: WCD934x chip id major 0x108, minor 0x1`.
**No ALSA card yet.**

**WLAN — closed negative, do not resume bisecting.** Both candidates cleared over
3 boots each, and building the known-good commit `d05e70c5e484` itself also fails.
The working image is `-dirty`; its source no longer exists anywhere. **The only
artifact that has ever brought `wlan0` up cannot be rebuilt from git.** Needs a
decision from Lance: hunt the lost delta, or adopt clean `d05e70c5e484` as baseline
and debug WLFW directly with `ath10k_core.debug_mask` + QMI tracing. Hardware is
fine (LineageOS Wi-Fi 243 Mbps).

**USB-C** — `dr_mode="otg"` + `usb-role-switch` kills USB entirely even with
`PHY_QCOM_QMP_USB=y`; system stays up, only the gadget dies. Next: `dr_mode="host"`
(needs no role provider), tested **alone**. Bus-powered host + auto role still need
new drivers upstream (no VBUS regulator, no PMI8998 TCPM).

**Camera** — specified and compiling, never probed. `docs/msm8998-camss-port-map.md`.

**ES9218P Quad DAC** — driver written, compiles, unprobed. Sits *downstream* of the
WCD9340, so it cannot be tested until playback works.

## Do this first

1. Boot **plain `snd3`** (`~/joan-images/boot-joan-snd3.img`) with only
   `log_buf_len=8M` added to the cmdline. **Do not** add
   `deferred_probe_timeout=0` — it caused a SLIMbus regression.
2. Confirm SLIMbus comes up (`SLIM SAT: Rcvd master capability` + codec chip id).
   It is **flaky**, not deterministic — retry before concluding.
3. Read what `msm-snd-sdm845` says with the full log intact. Previously only:
   `platform sound: deferred probe pending: msm-snd-sdm845: MultiMedia1: error
   getting cpu dai name`, with the sound device unbound and the deferred list empty.
4. Chase `PDR: service lookup for avs/audio failed: -6` — `qcom-ngd-ctrl` looks up
   the ADSP audio protection domain but msm8998 has **no PD maps**. Most likely
   reason SLIMbus is racy. **The problem is below the sound card, not in it.**

Bring-up sequence on device (ADSP firmware is absent from pmOS; stage to tmpfs):

```sh
# from nym-nest, as user@172.16.42.1 (sshpass -f /tmp/pmos-pass), sudo needs -tt
scp ~/joan-images/staging/adspfw/* user@172.16.42.1:/tmp/fwpath/qcom/msm8998/joan/
echo /tmp/fwpath > /sys/module/firmware_class/parameters/path
echo start > /sys/class/remoteproc/remoteproc1/state
```

## Traps that cost real time — do not repeat

- **Check which staging dir a repack points at.** Two "fix" images were built from
  a stale `staging/adsp-only` whose DTB predates the audio nodes; both boots tested
  the wrong kernel and one produced a false "theory disproven".
- **Validate a baseline before comparing against it.** ~20 boots went into a WLAN
  bisect comparing my builds against a *prebuilt binary* I had never confirmed I
  could rebuild. I couldn't.
- **One change per boot.** Bundling ADSP + USB changes cost a power-cycle and made
  the result unattributable.
- **`=m` is the recurring killer.** A RAM boot has no module tree. Five separate
  traps this session. Check this *first* when a subsystem is silently absent.
- **Nested shell/python quoting through ssh keeps breaking.** Write a plain script
  file, `scp` it, run it. Broke three times before I stopped hand-rolling it.
- **`ollama run` backgrounded with no stdin hangs** and never sends a request —
  `ollama ps` empty is the tell. Use the HTTP API.

## Unrelated but settled

Qwen3.8-27B measured and **rejected for interactive use**: 2.99 tok/s vs 26.96 for
`qwen3.6:35b-a3b` — 9× slower, matching the dense/MoE active-param ratio. Registered
in both harnesses labelled dense/slow, batch-only. Recorded in memory
`local_llm_tuning_skyforge.md`; do not re-derive.

Assisted-by: Claude-Code:claude-opus-5
Date: 2026-08-16
