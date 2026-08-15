# Aurel handoff: WCN3990 delete-key fix shape, audio/camera inventory, tethering harness

- **From:** Aurel Nymvale
- **To:** Lance's next Hermes/Aurel/Ember session
- **Harness/model:** Hermes Agent — `moa/deep-flash`
- **Date:** 2026-08-15, America/Los_Angeles
- **Standing goal:** upstream-shaped MSM8998/Joan support: close WCN3990 WLAN
  association reliability, verify faster tethering, and lay out audio/Quad DAC
  and camera bring-up.

## Read this first

This file is research scratch for audio/camera/tether inventory. The
authoritative held-off RAM-test handoff is
`docs/aurel-handoff-2026-08-15-to-next-session-wcn3990-delete-key-ram-test.md`.

This session stayed host-only. Lance later asked to hold the device test. No
boot.img was packaged, no partition was flashed, and the phone was not booted
into mainline.

Phone state at the later check (2026-08-15 03:32 PDT): LineageOS ADB
`LGUS9986e606d55`, no fastboot client.

## 1. WCN3990 pairwise delete-key `-110` — fix shape prepared

### Prior state

The 2026-08-15 AP-mode association campaign (see
`docs/ember-handoff-2026-08-15-wifi-ap-and-key-install.md`) showed:

- `NEW_KEY` install received a matching `SEC_IND` and connected successfully.
- `DEL_KEY` teardown did not receive a matching `SEC_IND` and timed out with
  `-110` after roughly 190 s.
- Classification: lost from the host's perspective, not late or mismatched.
- SMMU stream `0x1900` fault count was stable, so SMMU was not the trigger.

### What the upstream contract says

Upstream `ath10k` always waits for `HTT_T2H_MSG_TYPE_SEC_IND` after every
`install_key` request. The 2024 `ath10k@lists.infradead.org` thread around the
"key removal failure" RFC (e.g. msg17565–msg17576) discussed the same symptom on
WCN3990: firmware often does not emit a completion for delete-key operations,
so the driver stalls and eventually reports `-110`. The proposed fix shape was
to skip the wait for deletion-only commands, since the peer is already gone and
there is no key material to keep coherent.

This session verified the same code path in the local mainline tree and in the
LG downstream `qcacld-3.0` reference: downstream's `WMA` layer also special-
cases delete responses and does not hold the caller waiting for a completion
in the same way as install.

### The prepared fix

Branch: `joan/wcn3990-delete-key-no-wait`
Worktree: `/home/kumo02/vibe-coding-projects/coding/linux-mainline-v30-wcn3990-keyfix`
HEAD: `834154d6b0829b5fab79d087e1944725d25fecd0`
Base: `ghfork/joan/latest-clean-test` (`5fbb6db354d950ee3ab7f07deca7d5524ebce518`)

Patches (all signed, strict checkpatch clean, DT binding validated):

1. `dt-bindings: net: wireless: ath10k: add delete-key wait quirk`
   - Adds `qcom,ath10k-skip-pairwise-delete-key-wait` to
     `Documentation/devicetree/bindings/net/wireless/qcom,ath10k.yaml`.
2. `wifi: ath10k: make pairwise delete-key waiting optional`
   - Adds `bool skip_pairwise_delete_key_wait` to `struct ath10k`.
   - In `ath10k_install_key()`, when `cmd == DISABLE_KEY` and the quirk is set,
     complete `install_key_done` immediately and return without waiting for the
     firmware `SEC_IND`.
3. `arm64: dts: qcom: msm8998-lge-joan: skip pairwise delete-key wait`
   - Sets the new property on the `&wifi` node so joan uses the quirk.

This is scoped to **pairwise** keys. Group key deletion is left unchanged
because the original issue was observed on peer/vdev 0 pairwise teardown.

### Host qualification

- Worktree build of `drivers/net/wireless/ath/ath10k/{core.o,mac.o,snoc.o}`: exit 0.
- Full clean `Image.gz dtbs modules` later exited 0 as
  `7.2.0-rc2-g834154d6b082`.
- Image.gz SHA-256 `7336888c9c18ae007a935091b1c1614e8c79dac7289e4260b3db854507ad4551`.
- Joan DTB SHA-256 `7547b76040823108912db13d66250e26557110085908532d81c107cdb8c23dda`.
- boot.img was **not** packaged. Lance held the RAM test.
- Saved patch:
  `out/audit-20260815/wcn3990-delete-keyfix/wcn3990-delete-key-no-wait-834154d6b082.patch`
  (SHA-256 sidecar present).

### What a device test must prove

Run one RAM-only boot of the fix image, start AP mode with the same hostapd
config that previously failed, and associate the same problematic client(s).
Success criterion: the `failed to install key for vdev 0 peer ... -110`
message is absent, the peer stays associated, and at least one controlled
throughput sample can be measured. Failure criterion: the same `-110` still
appears, which would mean the delete-key wait was not the sole root cause.

## 2. Tethering throughput harness

### Why a harness is needed

Previous tethering numbers (e.g. 33.6 Mbps AP → nym-nest) were measured against
the live internet, so they conflated WLAN airtime, host forwarding/NAT, and
WAN variability. A reproducible local test is needed before claiming the fix
improves speed.

### Hosts prepared

- `nym-nest-family` (Arch): `iperf3` installed.
- `nym-fang-family` (Debian): `iperf3` installed.

### Proposed harness

`scripts/tether-throughput-harness.sh` will:

1. On the tethered joan host, start an `iperf3` server bound to the local
   downstream subnet address (e.g. `10.42.0.1`).
2. On the Wi-Fi client, run `iperf3 -c <joan_ap_ip>` for 10–30 s with multiple
   parallel streams, capturing sender/receiver throughput, retransmits, and
   CPU usage.
3. Optionally reverse direction (`-R`) to isolate RX vs TX airtime.
4. Record PHY rate from `iw dev <iface> station dump` and the hostapd/ath10k
   channel/width/TX power.
5. Keep all output under `out/audit-YYYYMMDD/<run>/` with SHA-256 sidecars.

For the first test, use the **joan AP → nym-fang** path so nym-nest only acts as
the USB tether/SSH jump host and does not add its own internet link into the
measurement. If NAT is still missing in kernel config (the 2026-08-15 build had
`CONFIG_NF_TABLES` absent and `CONFIG_IP_NF_IPTABLES=m`), continue to do NAT on
`nym-nest` and document the exact command sequence so it is reproducible.

### Acceptance criteria

- Baseline: reproduce the previous ~33.6 Mbps figure with the old AP-mode image.
- Fix test: with the delete-key quirk image, run the same harness and report
  whether the association is stable enough to complete a 30 s transfer at a
  comparable or higher rate.
- "Faster" must mean a reproducible local delta, not a one-off internet speed
  test.

## 3. Audio hardware inventory

### What the LG V30 (US998) actually has

From the downstream kernel and device trees:

- **Primary voice/playback codec:** Qualcomm WCD9340 ("Tavil"), reached over
  SLIMbus from the MSM8998 LPASS/APR.
- **Hi-Fi DAC:** ESS Technology ES9218P (Sabre), used for headphone/line-out
  high-quality audio. Downstream driver: `sound/soc/codecs/es9218p.c`.
- **Speaker amplifier:** NXP TFA98xx (likely TFA9872 on this board; exact part
  verified by downstream DT node at I2C address 0x34).
- **Microphones:** analog/digital mics routed through Tavil and the QDSP6 audio
  DSP.
- **DSP audio:** Qualcomm QDSP6 / APR / q6asm, required for any PCM/voice path.

### Downstream topology evidence

Key downstream files examined:

- `arch/arm64/boot/dts/lge/msm8998-joan/msm8998-joan-common/msm8998-joan-common-sound.dtsi`
- `arch/arm64/boot/dts/lge/msm8998-joan/msm8998-joan_nao_us/msm8998-joan_nao_us-sound.dtsi`
- `sound/soc/codecs/es9218p.c`
- `sound/soc/codecs/tfa98xx.c` (or equivalent NXP amp driver)

Downstream `CONFIG_SND_SOC_ES9218P` is built-in (`=y`) in the joan defconfig.
The ES9218P driver implements DAPM, mixer controls, and a Hi-Fi mode switch.

### Mainline gaps

- **No ES9218P driver in mainline.** The downstream driver is GPL-2.0 and is the
  starting reference, but it uses legacy ASoC APIs and will need porting.
- **No TFA98xx/TFA9872 codec mainline.** `tfa989x.c` exists for some TFA parts
  but does not match the exact register map used by LG's TFA98xx driver.
- **SLIMbus/WCD9340 support is present in mainline** (`wcd934x.c`, `sdw-
slimbus`,
  `qcom,lpass-apple-dtp` etc.), but MSM8998 SLIMbus controller + LPASS/ADSP audio
  nodes are missing from the joan DTS.
- **Joan DTS has no audio card node.** There is no `sound` node with DAI links,
  no `quaternary mi2s`, and no SLIMbus codec references. This is the first
  blocker.
- **QDSP6 remoteproc/firmware chain is needed before any audio path works,**
  including the Quad DAC. ADSP bring-up is therefore a prerequisite.

### Quad DAC specifically

The ES9218P is the hardware that implements the Quad DAC feature. In downstream:

- It is on an I2C bus (address and GPIO reset defined in the joan sound DTSI).
- It is selected via a DAPM mux that switches headphone output between Tavil
  and ES9218P.
- There is no upstream driver; bringing it up is a dedicated sub-project.

### Suggested first audio steps

1. Add a minimal `sound` card node to `msm8998-lge-joan.dts` with a dummy DAI
   link to prove LPASS probe and ASoC registration.
2. Port the ES9218P codec driver to current ASoC APIs and add it as an I2C
   codec.
3. Port or write a minimal TFA9872 speaker driver.
4. Bring up ADSP/QDSP6 firmware loading first; without it even Tavil playback
   will not work.

## 4. Camera hardware inventory

### What the LG-US998 actually has

From the downstream device tree and the LineageOS vendor blobs:

- **Rear wide (primary):** Sony IMX351
- **Rear telephoto:** Samsung S5K3M3
- **Front:** Hynix HI553

Vendor blobs found:

- `proprietary/vendor/lib/libmmcamera_hi553.so`
- References to IMX351/S5K3M3 in `drivers/media/platform/msm/camera_v2/sensor/`
  and the camera DT.

### Downstream camera topology

Files examined:

- `arch/arm64/boot/dts/lge/msm8998-joan/msm8998-joan-camera/msm8998-joan-camera_rev_0.dtsi`
- `drivers/media/platform/msm/camera_v2/sensor/io/` and `sensor_init.c`

Downstream uses the legacy Qualcomm `camera_v2` framework with:

- `qcom,cam-sensor` nodes for each sensor.
- `qcom,sensor-name` properties (e.g. "imx351", "s5k3m3", "hi553").
- CCI, CSIPHY, CSID, ISPIF, VFE resources in the DT.
- Actuator, EEPROM, and OIS child nodes per sensor.

### Mainline gaps

- **No `qcom,msm8998-camss` binding in upstream CAMSS.** The upstream driver
  supports:
  - `msm8916-camss`, `msm8939-camss`, `msm8953-camss`, `msm8996-camss`,
    `qcm2290-camss`, `qcs8300-camss`, `sa8775p-camss`, `sc7280-camss`,
    `sc8280xp-camss`, `sdm660-camss`, `sdm670-camss`, `sdm845-camss`,
    `sm6150-camss`, `sm6350-camss`, `sm8250-camss`, `sm8550-camss`,
    `sm8650-camss`, `x1e80100-camss`.
  - **MSM8998 is absent.** It is closest to `msm8996-camss` (CAMSS_8x96) but has
    three CSIPHYs, three CSIDs, two VFEs (VFE 4.7) and ISPIF, so a new resource
    table is required.
- **No sensor drivers for IMX351, S5K3M3, or HI553** in mainline.
- **Joan DTS has no CAMSS, CCI, or sensor nodes.** The upstream driver would have
  nothing to bind to even if it supported MSM8998.
- **Sensor firmware/EEPROM calibration** lives in vendor partitions; a full
  bring-up would need careful handling of closed blobs.

### Suggested first camera steps

1. Add a `qcom,msm8998-camss` compatible resource table to the upstream CAMSS
   driver (or a local patch) based on the `msm8996-camss` template.
2. Add CAMSS/CCI/CSIPHY/CSID/VFE nodes to `msm8998.dtsi` or the joan DTS.
3. Port or write minimal I2C/CCI sensor drivers for IMX351, S5K3M3, HI553,
   starting with `libv4l2` subdev skeletons and the downstream register tables.
4. Validate only static probe and `media-ctl` topology first; do not attempt
   capture until the pipeline is stable.

## 5. Files produced this session

- `docs/aurel-handoff-2026-08-15-wcn3990-audio-camera-throughput.md` — this file.
- `out/audit-20260815/wcn3990-delete-keyfix/wcn3990-delete-key-no-wait-834154d6b082.patch`
- `out/audit-20260815/wcn3990-delete-keyfix/wcn3990-delete-key-no-wait-834154d6b082.patch.sha256`
- `out/audit-20260815/wcn3990-delete-keyfix/wcn3990-delete-key-no-wait-834154d6b082.metadata.txt`

## 6. Next actions

| Priority | Task | Owner | Blocker |
|---|---|---|---|
| 1 | Package a hash-bound boot.img from the sealed `834154d6b082` Image.gz+DTB | next session | Lance must ask; do not do this from the held-off handoff |
| 2 | One-shot RAM boot to classify teardown `-110` and take one local iperf3 sample | Lance + agent | Fresh approval must name the new image SHA |
| 3 | Run `scripts/tether-throughput-harness.sh` against baseline + fix image | Agent | Device test from #2 |
| 4 | Add minimal `sound` node to joan DTS and scope ADSP bring-up | Agent | Device test time |
| 5 | Add `qcom,msm8998-camss` resource table and DT nodes | Agent | Research + host validation |

## 7. Safety boundaries

- No device flash.
- One `fastboot boot` per runner with fresh SHA verification.
- No audio playback/recording or camera capture without explicit later approval.
- No cellular registration/transmission tests.

Assisted-by: Hermes-Agent:moa/deep-flash
