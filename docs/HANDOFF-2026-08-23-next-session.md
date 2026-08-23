# LG V30 (joan) — handoff, 2026-08-23

Written at the end of a session that ran low on usage. Everything below is
either committed or preserved as a file; nothing important lives only in chat.

---

## THE ONE THING TO READ FIRST

There is an **uncommitted change in the kernel tree that is a regression**, made
by a parallel `/code-review high` session. Do not commit it as-is.

    linux-mainline-v30, branch joan/q6voice-mvm-probe
     M sound/soc/qcom/qdsp6/q6voice.c

Preserved verbatim at `other-session-q6voice-rename.patch` (nothing deleted).

It makes two changes, both wrong, and both **untested** — while the code they
replace was verified working on hardware:

### 1. Session name `"11C05000"` -> `"VoiceMMode1"` — WRONG

The vendor driver defines **both** strings, and they are different things:

    q6voice.h:1804  #define VOICEMMODE1_NAME      "VoiceMMode1"
    q6voice.h:1810  #define VOICEMMODE1_VSID_STR  "11C05000"

* `VOICEMMODE1_VSID_STR` = `"11C05000"` is what `q6voice.c` actually copies into
  the APR payload (`mvm_session_cmd.mvm_session.name`) at lines 885 and 1009.
  **This is the wire format.**
* `VOICEMMODE1_NAME` = `"VoiceMMode1"` is used in `msm-pcm-voice-v2.c:272` as an
  **ALSA PCM substream id** — a userspace-facing PCM name, never sent over APR.

The review confused the PCM id for the session name. Understandable — the define
sits six lines above the right one — but it is not what goes on the wire.

Decisive evidence: `"11C05000"` **worked on hardware**, four reproducible cycles,
every command status 0. `"VoiceMMode1"` has never been run.

### 2. Removing `char name[SESSION_NAME_LEN]` from the CVP v2 struct — WRONG

The vendor struct `vss_ivocproc_cmd_create_full_control_session_v2_t` ends with
`char name[SESSION_NAME_LEN]`. Removing it shortens the packet 64 -> 44 bytes.
The 64-byte form was accepted by the ADSP with status 0.

### Recommended action

Revert the working-tree change (`git checkout -- sound/soc/qcom/qdsp6/q6voice.c`)
**after confirming with Lance**, since it is a sibling session's work. If there
is any doubt, test both on hardware — it is one boot to settle.

Do not treat this as "the review was wrong about everything": the rest of that
session's findings may well be good. This specific change is a regression.

---

## What works, verified on hardware

### Cellular data — WORKING
Two changes, from the previous phase:
1. `wrr_weight = 1` in `drivers/net/ipa/gsi.c` (was 0; a zero weight starves the
   channel in the GSI round-robin scheduler). **Real mainline bug, one line.**
2. `ipa.lowmem=1` — a scratch page mapped at IOVA 0 (workaround, not a fix).

Verified 20/20, 5/5, 8/8 packets to public IPv6 DNS, reproducible across boots.

An upstream submission for the WRR fix is prepared and unsent:
`~/.ember/workspace/joan-cellular-2026-08-23/outgoing/` (patch, email mockup,
send instructions). Sending is Lance's call.

### Voice session on the ADSP — WORKING (new this session)

Mainline had **no** Qualcomm voice-call support at all: `sound/soc/qcom/qdsp6/`
is data-path only (ASM/AFE/ADM). Added `q6voice.c`, a Core Voice Driver client.

Full sequence, every step status 0 on joan:

| # | Service | Command | Opcode |
|---|---------|---------|--------|
| 1 | MVM | CREATE_PASSIVE_CONTROL_SESSION | `0x000110ff` |
| 2 | CVS | CREATE_PASSIVE_CONTROL_SESSION | `0x00011140` |
| 3 | MVM | ATTACH_STREAM | `0x0001123c` |
| 4 | CVP | CREATE_FULL_CONTROL_SESSION_V2 | `0x000112bf` |
| 5 | CVP | ENABLE | `0x000100c6` |
| 6 | MVM | ATTACH_VOCPROC | `0x0001123e` |
| 7 | MVM | START_VOICE | `0x00011190` |

Plus full reverse-order teardown. Four start/stop cycles on one boot, distinct
MVM handles each time (`0x0020`, `0x0066`, `0x00ad`, `0x00f4`), zero timeouts.

### Sound card — WORKING (new this session)

`/proc/asound/cards` was empty. Cause was **not** the audio stack: three unset
config symbols. Fragment committed at `lg-v30-port/configs/joan-audio-voice.config`.

    CONFIG_QCOM_Q6V5_PAS=m     boots the ADSP; unset = no remoteproc, no APR,
                               no sound card, while every audio module loads fine
    CONFIG_SND_SOC_TFA989X=m   speaker amp, tertiary MI2S dai-link
    CONFIG_SND_SOC_ES9218P=m   Quad DAC, quaternary MI2S dai-link

A sound card is all-or-nothing: one unresolvable codec dai leaves the whole card
in deferred probe forever, so a missing *speaker amp* driver also took down the
unrelated SLIM/WCD link — the earpiece and call mic. Now:

    0 [LGV30]: sdm845 - LG-V30
    pcmC0D0c  pcmC0D0p  pcmC0D1c  pcmC0D1p

### Earpiece — chain powers up (new this session)

Resolves the question left open in the 2026-08-21 handoff. The earpiece is on
the **WCD9340's EAR PA via RX INT0** — not behind the ES9218P or TFA98xx. Stock
confirms it:

    <path name="handset" />
    <ctl name="RX0 Digital Volume" value="84" />
    <ctl name="EAR PA Gain" value="G_6_DB" />

Working mainline route (whole chain reads `On` during playback):

    SLIMBUS_0_RX Audio Mixer MultiMedia1 = 1
    SLIM RX0 MUX          = AIF1_PB
    RX INT0_1 MIX1 INP0   = RX0
    RX INT0_1 INTERP      = RX INT0_1 MIX1
    RX INT0 DEM MUX       = CLSH_DSM_OUT     <-- NOT NORMAL_DSM_OUT
    RX0 Digital Volume    = 84               <-- S8_TLV offset: 84 is 0 dB
    EAR PA Volume         = 4

`RX INT0 DEM MUX` must be `CLSH_DSM_OUT`: it is the only value with a DAPM route
in mainline's wcd934x. `NORMAL_DSM_OUT` (what stock's table shows) has none, and
setting it silently breaks the path with no error.

**NOT VERIFIED: audibility.** DAPM says the chain is powered; nobody has listened.
That needs a human with the phone at their ear. It is the cheapest high-value
next step.

---

## What does NOT work

* **VoLTE** — no AP-side IMS/SIP stack. joan's modem exposes **zero** IMS QMI
  services (18/19/31/32/33/40 all absent) despite being fully provisioned (TMO
  PDC config Active, `IMS voice support: yes`, ISIM present, IMS APN = profile
  10). The 700-range services are not IMS; LG's table maxes at 227.
* **Phone calls** — needs the above plus real audio through the voice session.

### Media path — SETTLED, do not re-derive

VoLTE media goes through the **modem's vocoder (CVD)**, not AP-side RTP. Stock
HAL contains `voice_start_call`, `VOICEMMODE`, `VSID`, `cvd_version`; VoLTE
reuses the same `voice-call *` mixer paths as a CS call with only the VSID
differing. So no AP-side vocoder/jitter buffer/RTP stack is needed — but a
kernel voice driver is, which is what `q6voice.c` now provides.

---

## Open bugs

1. **Module reload leaves the ADSP silent.** After rmmod/modprobe all three
   services rebind (`bound` mask 7), APR devices unchanged, command is sent, no
   response ever arrives; persists across retries a minute later. **Not** leaked
   sessions — teardown is clean and the 4-cycle test rules out session count.
   Cause unknown. Workaround: reboot between reloads.
   Prime suspect: the driver has **no `.remove` callback**.
2. **IOVA 0x38** (from the data phase) — IPA *reads* an unmapped address at
   IOVA 0x38 and consumes the value: zeros are benign, `0xa5` silently kills the
   data path with no fault and no crash. Root cause unknown; `ipa.lowmem=1`
   papers over it. Suggested next step: poison only a small window to find which
   bytes matter, starting at `0x38`-`0x3f`.
3. `wcd934x-slim: missing qcom,mbhc-buttons-vthreshold-microvolt` — cosmetic.
4. `qcom-soundwire: din-ports (2) mismatch with controller (6)` — logged with
   `dev_err` but `drivers/soundwire/qcom.c` then overrides with the DT value and
   continues. Noisy, not fatal. Ignore.

---

## Rig notes — these cost real time to learn

* **After every `fastboot boot`, re-add the host IP.** The phone's USB gadget
  enumerates as a *new* netdev with a new MAC, so `172.16.42.2/24` is gone. The
  phone looks dead while being perfectly healthy.
  `sudo ip addr add 172.16.42.2/24 dev enp0s29u1u5`
* **Do not sweep `/sys/kernel/debug/regmap/*/registers`.** Reading a regmap whose
  hardware is unpowered blocks; it wedged the phone hard enough to need a
  physical power cycle. Target one regmap by name.
* **Build the kernel and its modules from the same tree state and reboot into the
  pair.** Do not binary-patch module vermagic to dodge a rebuild — it works only
  while the string length happens to match, then fails confusingly.
* **Install modules, then reboot.** Modules installed while the phone is already
  up are never loaded — udev's coldplug has already run.
* **`echo b > /proc/sysrq-trigger`** to get back to Android; plain `reboot` wedges
  it. Then `adb reboot bootloader`, then `fastboot boot`.
* Detach long device cycles on nest and poll the log, or ssh timeouts eat results:
  `setsid bash -c "bash /tmp/cycle.sh > /tmp/log 2>&1" < /dev/null > /dev/null 2>&1 &`
* Build host is **nym-skyforge**; flashing is from **nym-nest** (skyforge's xHCI
  cannot talk to LG aboot).

---

## Where everything is

| What | Where |
|---|---|
| q6voice driver + DT | `linux-mainline-v30`, branch `joan/q6voice-mvm-probe` (4 commits) |
| Pushed | `ghfork` = ShapeShifter499/linux-lg-v30-joan, **PR #9** |
| Writeup (~1500 lines) | `lg-v30-port/docs/2026-08-23-cellular-data-gsi-uplink.md` |
| Config fragment | `lg-v30-port/configs/joan-audio-voice.config` |
| WRR upstream submission | `~/.ember/workspace/joan-cellular-2026-08-23/outgoing/` |
| Other session's regression | `other-session-q6voice-rename.patch` (this dir) |

PR #9 is 4 files / 619 lines, base `joan/latest-clean-test`. `/code-review ultra`
could not run locally: `.git` is 15G and ultra bundles the repo. The PR form
(`/code-review ultra 9`) avoids that.

---

## Suggested next steps, in order

1. **Settle the naming conflict above.** One boot. Everything else builds on it.
2. **Listen to the earpiece.** The route is known and powers up; it needs ears.
   If it is audible, that closes a question open since 2026-08-21 and confirms
   the output half of call audio.
3. **Add the `.remove` callback**, then re-test module reload — likely fixes
   open bug #1.
4. **Wire the voice session to real audio**: the vocproc is built against
   SLIMBUS_0_RX/TX (`0x4000`/`0x4001`) but nothing starts those AFE ports. This
   is where a PCM front-end belongs instead of debugfs.
5. **The call mic**, which is the other half — stock has dedicated
   `voice-call-handset-mic` and `voice-call-submic1..3` paths.
6. **IMS/SIP** is the remaining VoLTE blocker and is a large separate project;
   it should be a device-neutral userspace daemon, packaged for the pmOS
   packages repo and eventually pmaports.
