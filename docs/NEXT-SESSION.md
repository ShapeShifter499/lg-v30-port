# LG V30 (joan) — next session start here

- **From:** Ember Nymbrand (agent-ember) · Claude-Code:claude-opus-5 · 2026-08-16 (session B)
- **Full detail:** `docs/ember-handoff-2026-08-16b-pd-mapper-fixed-qmi-is-next.md`
- **WLAN detail:** `docs/ember-wlan-delta-recovered-2026-08-16.md`

## State

Everything is banked and pushed.

| | |
|---|---|
| `ghfork/joan/latest-clean-test` | `7187fbbb5` (full history) |
| `ghfork/master` | `63a15f526` (device-verified only; history amended 2026-08-16) |
| kernel tree | `~/vibe-coding-projects/coding/linux-mainline-v30-usb-otg`, branch `joan/usb3-otg-bringup`, clean |
| build dir | `/data/buildcache/kbuild/build-adsp-only` — build **in place**, no `cp -a` |
| test image | `~/joan-images/boot-joan-snd-pdm.img` on nym-nest |
| Deck | Shared Tasks board 4, card **98** |

Phone: LG V30 `LGUS9986e606d55` on nym-nest. **RAM boots only — never flashed.**
Recover with `adb reboot` or a 10 s power hold.

## Do this first

**Two independent lanes are ready. Pick one; don't interleave them.**

### Lane A — WLAN, one boot from a real answer

The bisect was a confound: `CONFIG_ATH10K_DEBUG` / `ATH10K_DEBUGFS` are the
*only* difference between the working image and every failing one, and turning
them on is what breaks Wi-Fi. Proven by extracting the embedded `.config` from
both binaries (`CONFIG_IKCONFIG=y`).

1. Build `joan/latest-clean-test` with **both symbols cleared**.
2. RAM boot, bring up `rmtfs`, check for `wlan0` and QMI service 69 (WLFW).
3. If it comes up, WLAN is reproducible from committed state and the real target
   becomes *why bring-up is timing-fragile enough that logging breaks it*.

This is the cheapest high-value test available.

### Lane B — audio, and the wall moved

The PD lookup fix landed and is **verified on device**: `avs/audio` now resolves
and the audio PD reports `SERVREG_SERVICE_STATE_UP`. Still no ALSA card. The
blocker is now **below SLIMbus**:

```
qcom,slim-ngd-ctrl 171c0000.slim-ngd: QMI wait timeout
PDR: msm/adsp/audio_pd register listener txn wait failed: -110
```

The ADSP never registers **QMI service 769 (SLIMbus control service)** — checked
with `qrtr-lookup` across three boots. APR over the same GLINK edge works fine
(all four Q6 services register), so this is specific to QMI/QRTR.

Investigate the QMI layer to the ADSP. **Not** the sound node, **not** SLIMbus.
Open questions: why QMI transactions time out at `-110` while APR is healthy;
whether the ADSP needs something before it starts its SLIMbus service; whether
a `tms/pdr_enabled` equivalent is wanted (joan's `modemr.jsn` advertises it,
`mpss_root_pd` does not carry it).

Worth trying alongside: now that PD maps work, add
`qcom,protection-domain = "msm/adsp/audio_pd"` to the Q6 service nodes, as
sdm845 does. It was omitted on a false premise.

## Resolved: the false PD-maps claim is fixed

`719e34de5` claimed *"msm8998 does not run the audio PD split -- its firmware
carries no PD maps."* False; joan ships six. Lance approved amending, so master
was rewritten: `719e34de5` → `a72f66c1d`, and `ghfork/master` is now
`63a15f526`. Verified message-only — both old and new histories resolve to tree
`f16de7d1a`. The corrected body says the property is dropped because the
*kernel's* msm8998 PD table had no ADSP domains, cites `adspua.jsn`, and points
at revisiting `qcom,protection-domain`.

⚠️ **`joan/latest-clean-test` still carries the original `c43b281a5` with the
wrong body.** It was not rewritten — that would force-push six commits of the
shared full-history branch. Fix it when preparing the series for upstream, or
ask Lance.

## Bring-up sequence on device

```sh
# after every phone reboot the USB net link must be rebuilt by hand:
sudo ip link set enp0s29u1u5 up
sudo ip addr add 172.16.42.2/24 dev enp0s29u1u5

# then, from nym-nest (sshpass -f /tmp/pmos-pass, sudo needs -tt):
scp ~/joan-images/staging/adspfw/* user@172.16.42.1:/tmp/adspfw/
echo /tmp/fwpath > /sys/module/firmware_class/parameters/path
echo start > /sys/class/remoteproc/remoteproc1/state
```

`~/joan-images/staging/fastboot-adsp.sh`-style orchestration exists at
`/tmp/fastboot-adsp.sh` on nym-nest — it does Android → RAM boot → net → ADSP in
one shot, ADSP started at 33 s.

## Don'ts — each of these cost real time

- **Don't `cp -a` a build dir and add `KCFLAGS`.** Read `.<obj>.cmd` first to see
  what the dir was actually built with. Adding `-ffile-prefix-map` changed every
  argv and cold-missed ccache: 2200 objects / 20+ min vs 5 objects / 7m40s in
  place.
- **Don't use `deferred_probe_timeout=0`.** It makes
  `driver_deferred_probe_check_state()` return `-ETIMEDOUT` for genpd and iommu
  lookups (`drivers/base/dd.c:292`). Use a large value — `300` worked. But the
  default `10` *will* drop the sound card before a hand-started ADSP exists.
- **Don't judge audio from an ADSP restart.** `echo stop` times out waiting for
  shutdown and the PD listener then fails; only fresh boots are meaningful.
- **Don't trust `grep -c "[p]attern"` for "is anything using this".** Your own
  shell command line matches. Bit me again this session.
- **Don't assume a `-dirty`-looking image is the one you think.** Check the
  version string in the actual file; several neighbours were `-dirty` and the
  working one was not.

## Unrelated but settled

`build-snd-pdm` deleted (5.6 GB) with Lance's approval. A monthly `duperemove`
pass on `/data` ran ~15 h during this session and made all disk timings noisy —
check for it before blaming a build.

Assisted-by: Claude-Code:claude-opus-5
Date: 2026-08-16
