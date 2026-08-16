# Handoff 2026-08-16 (session B): PD lookup fixed on hardware; ADSP QMI is the next wall

- **Written-by:** Ember Nymbrand (agent-ember)
- **Agent-harness:** Claude-Code:claude-opus-5
- **Date:** 2026-08-16, America/Los_Angeles
- **Authorization:** Lance authorized the test boots, the pushes below, the
  removal of `build-snd-pdm`, and chose the WLAN approach.

## Banked

| what | where |
|---|---|
| full history | `ghfork/joan/latest-clean-test` → `7187fbbb5` |
| device-verified only | `ghfork/master` → `d649b6a31` (cherry-picks `1c640c290`, `d649b6a31`) |
| docs + evidence | this repo, branch `aurel/card94-reset-script` |
| test image | `~/joan-images/boot-joan-snd-pdm.img` on nym-nest, sha256 `5edc47cd…3238` |
| build dir | `/data/buildcache/kbuild/build-adsp-only` (in place; `build-snd-pdm` deleted) |

Kernel built **clean** this time: `7.2.0-rc2-g7187fbbb5675`, no `-dirty`.

## Audio: the PD lookup is fixed, verified on device

Root cause of `PDR: service lookup for avs/audio failed: -6`: `msm8998_domains[]`
in `drivers/soc/qcom/qcom_pd_mapper.c` listed only the two modem PDs. The
in-kernel locator answered `SERVREG_LOC_GET_DOMAIN_LIST` without ever offering
`msm/adsp/audio_pd`, so `pdr_locate_service()` returned `-ENXIO`.

**The previous handoff's premise was wrong.** msm8998 does have PD maps — joan
ships six `.jsn` files in `/firmware/image` (the `modem` partition):

```
adspr.jsn    msm/adsp/root_pd     74   tms/servreg
adspua.jsn   msm/adsp/audio_pd    74   avs/audio, tms/servreg
modemr.jsn   msm/modem/root_pd   180   tms/servreg, tms/pdr_enabled
modemuw.jsn  msm/modem/wlan_pd   180   kernel/elf_loader, tms/servreg, wlan/fw
slpir.jsn    msm/slpi/root_pd     90   tms/servreg
slpius.jsn   msm/slpi/sensor_pd   90   tms/servreg
```

They match the kernel's existing generic structs exactly, and `qrtr-lookup` on
the running device independently shows the ADSP serving servreg at instance 74.
Banked under `docs/evidence/2026-08-16-joan-pd-maps/` with sha256sums.

**Verified on hardware** (`docs/evidence/2026-08-16-pd-mapper-boots/boot1-pd-up.txt`):

```
[391.763426] PDR: Indication received from msm/adsp/audio_pd, state: 0x1fffffff, trans-id: 1
```

`0x1fffffff` is `SERVREG_SERVICE_STATE_UP`. The `-6` failure is gone.

⚠️ **`719e34de5` on master carries a claim now known to be false** — "msm8998
does not run the audio PD split -- its firmware carries no PD maps" — and that
claim is why `qcom,protection-domain` was omitted from the Q6 services. Needs
Lance's call: amend the pushed commit, or fix it when the series is prepared for
upstream. **Do not rewrite pushed history without asking.**

Now that PD maps work, adding `qcom,protection-domain = "msm/adsp/audio_pd"` to
the Q6 service nodes (as sdm845 does) is worth trying.

## Also fixed and verified: the q6 DAI children

They were **uncommitted** at the start of this session, despite the previous
handoff saying nothing was dirty — but they *were* in the tested DTB. Banked as
`1c640c290`. Device-verified: `q6asm-dai`, `q6afe-dai` and `q6routing` all bind,
and the sound card's deferred reason moved from
`MultiMedia1: error getting cpu dai name` to `SLIM Playback: codec dai not found`.

## The next wall: ADSP QMI, not SLIMbus

No ALSA card yet. The chain now stops one layer lower than the sound node **and
lower than SLIMbus**:

```
[34.408516] qcom,slim-ngd-ctrl 171c0000.slim-ngd: QMI wait timeout
[38.628673] PDR: msm/adsp/audio_pd register listener txn wait failed: -110
```

`qcom_slim_ngd_up_worker()` waits **1 second** for `ctrl->qmi_up`, which is
completed by `qcom_slim_ngd_qmi_new_server()` when the ADSP registers **QMI
service 769 (SLIMbus control service)**. Across three boots this session, 769
**never appeared at all**. The ADSP is up, GLINK is fine, and APR registers all
four Q6 services — but the ADSP does not expose its SLIMbus QMI service, and PDR
listener registration also times out with `-110`.

The earlier session's boot *did* get 769 within ~4 s (it failed later, at
`select h/w instance`). So 769 registration is itself nondeterministic across
firmware boots, and this session got the unlucky side three times.

**Ruled out this session: ADSP start latency.** The hypothesis was that starting
the ADSP at 391 s rather than ~32 s was the difference. Tested directly with an
automated cycle that started it at **33 s** — 769 still absent. Negative, clean.

Next investigation should be the QMI/QRTR layer to the ADSP, not SLIMbus and not
the sound node:
- Why do QMI transactions to the ADSP time out (`-110`) while APR over the same
  GLINK edge works?
- Does the ADSP need something before it starts its SLIMbus service — a
  `tms/pdr_enabled` service, an audio PD restart, or a QMI client the kernel is
  not providing?
- `modemr.jsn` advertises `tms/pdr_enabled`, which `mpss_root_pd` does not carry.
  Whether the ADSP wants an equivalent is unexamined.

## WLAN: the lane is reopened — it was a config confound

Full writeup: `docs/ember-wlan-delta-recovered-2026-08-16.md`.

The previous handoff closed WLAN as unreproducible, on the basis that the only
working image was `-dirty` with lost source. **It is not `-dirty`.** The image
behind run `WIFI-20260814T183233Z` is `boot-joan-wifi-d05e70c5e.img`, version
string `7.2.0-rc2-gd05e70c5e484`, clean.

`CONFIG_IKCONFIG=y`, so every image embeds its own `.config` between `IKCFG_ST`
and `IKCFG_ED`. Extracting from the working image and the failing control — both
clean builds of the same commit, so source is identical by construction — leaves
config as the only possible variable. It differs in exactly two symbols:

| | working | failing |
|---|---|---|
| `CONFIG_ATH10K_DEBUG` | not set | `=y` |
| `CONFIG_ATH10K_DEBUGFS` | not set | `=y` |

Nothing else, across 4,932 set symbols. The debug instrumentation added to chase
the WLAN bug is what breaks WLAN, and every bisect arm inherited it — so the
bisect was measuring its own instrumentation.

**Not yet confirmed by a boot.** What is proven is *which* variable differs.
Both configs are banked under `docs/evidence/`.

Note the audio build lineage still carries `CONFIG_ATH10K_DEBUG=y`. Any build
meant to have working Wi-Fi must clear both symbols.

## Mechanisms worth not re-deriving

**`deferred_probe_timeout=0` is not "disabled".** `drivers/base/dd.c:292`:
once initcalls are done, a timeout of 0 makes
`driver_deferred_probe_check_state()` return `-ETIMEDOUT` instead of
`-EPROBE_DEFER`, which hits genpd (`drivers/pmdomain/core.c:3382`) and iommu
(`drivers/iommu/iommu.c:3079`) dependency lookups. It *does* also stop the
deferred list ever being flushed, which is why the card kept retrying.

**`CONFIG_DRIVER_DEFERRED_PROBE_TIMEOUT=10` is the reason the card was dropped.**
The ADSP is hand-started ~35 s in, long after the 10 s flush. This session used
`deferred_probe_timeout=300`, which keeps `check_state()` returning
`-EPROBE_DEFER` *and* keeps the card alive. Confirmed: the card was still on the
deferred list at 391 s. Caveat: once the 300 s timer does fire, the timeout is
set to 0 and the `-ETIMEDOUT` hazard returns.

**The previous `=0` "SLIMbus regression" was probably misattributed** — SLIMbus
failure is nondeterministic, and `=0` was likely coincidence.

## Traps hit this session

- **`cp -a` of a warm build dir does not keep ccache warm if you add flags.** I
  added `KCFLAGS=-ffile-prefix-map=$OUT/=` copied from an older script. The
  original build dir used **no** `-ffile-prefix-map` (verified from
  `.qcom_pd_mapper.o.cmd`), so every argv changed and ccache direct-mode missed
  on the whole tree: 2200+ objects, 20+ min, unfinished. Rebuilding **in place**
  with the original flags: 5 objects, 7m40s. **Read `.<obj>.cmd` before assuming
  what a build dir was built with.**
- **`-j16` on a 12-core box** while a 15-hour `duperemove` pass held `/data`.
  Check `nproc` and check for background I/O before blaming the build.
- **The `pgrep`/`grep -c` self-match trap again.** `grep -c "[b]uild-snd-pdm"`
  returned 2 because *my own shell command line* contained the literal string.
  The bracket trick only hides the grep, not the parent shell.
- **The USB net link is configured by hand and does not survive a phone
  reboot.** `enp0s29u1u5` is unmanaged by networkd; after every re-enumeration
  you need `sudo ip link set enp0s29u1u5 up` and
  `sudo ip addr add 172.16.42.2/24 dev enp0s29u1u5`. Nothing restores it.
- **Restarting the ADSP degrades it.** `echo stop` gives
  `timeout waiting for shutdown response`, and after restart the PD listener
  registration fails. Judge results from a fresh boot, not a restart.

Assisted-by: Claude-Code:claude-opus-5
Date: 2026-08-16
