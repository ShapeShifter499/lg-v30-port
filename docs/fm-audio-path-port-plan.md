# FM audio path port plan (btfmslim → mainline), for Deck #163

Written-by: Fulgor Nymvale (agent-fulgor-zcode)
Agent-harness: ZCode:GLM-5.3-Flash
Date: 2026-09-27
Status: plan only, no code written yet

## Hardware path to reproduce

WCN3990 FM audio (analog baseband digitised in the BT chip) → **second
SLIMbus** (the BT/FM slave on the NGD bus, not the Tavil/WCD934x one) →
ADSP (q6asm "BT-FM" stream) → SoC audio output.  Downstream shipped
this as a slimbus client driver + ASoC codec + WCN3990 port config.

## Downstream sources (android_kernel_lge_msm8998)

- `drivers/bluetooth/btfm_slim.c` — slimbus client: element access with
  retry (`slim_change_val_element`, vendor API), device status/logical
  address handling, debugfs.
- `drivers/bluetooth/btfm_slim_codec.c` — ASoC codec (old API): DAIs for
  BT/FM playback, DAPM, the interface the machine driver binds.
- `drivers/bluetooth/btfm_slim_wcn3990.c/.h` — WCN3990 port map
  (`CHRK_SB_PGD_PORT_TX1_FM = 1`, `TX2_FM = 2`), `btfm_slim_chrk_hw_init()`
  vendor init, port enable/disable helpers.
- Reference DT: the WCN3990 slim slave node under the NGD bus in LG's
  msm8998 dtsi (grep `btfm` / `slim` in the lge dts dirs).

## Mainline translation notes

- Vendor slimbus calls map onto mainline `slimbus` core: element writes →
  `slim_write()`; ports/streaming → the `slim_stream_*()` API (see
  `sound/soc/codecs/wcd934x.c` for an in-tree user of the modern API on
  this SoC family).
- The codec must become a modern `snd_soc_component` (DAI + DAPM), not the
  legacy `snd_soc_codec`.
- Machine side: the ADSP path needs a BE DAI on the q6asm side ("BT-FM"
  back-end) and a DPCM route; the joan machine driver (sdm845.c-based
  sound card) currently has no BT-FM BE — one has to be added or the
  q6afe "SLIMBUS_?" port chosen to match what the ADSP's FM sink expects
  (downstream names it via `qcom,cdc-btfm` / AFE port
  `AFE_PORT_ID_SLIMBUS_0_RX`-style constants — confirm the exact AFE port
  id from the downstream machine/AFE headers before wiring).
- DT: WCN3990 FM slim device node (elementary address from the downstream
  dtsi) under the NGD controller the radio uses; the mainline slim-ngd
  driver for msm8998 must list the device.

## Open questions (resolve on the bench)

1. Which NGD instance/port the WCN3990 FM sits on (slim@17240000 per the
   2026-09-26 handoff note) and its EA (elementary address).
2. The exact AFE/q6asm port id for the BT-FM sink in the ADSP build.
3. Whether the FM audio needs the `hci_qca` radio driver to also enable a
   vendor op (downstream ties slimbus audio to the BT power state).

## Suggested order

1. Port `btfm_slim.c` core as a slim_driver with the element read/write
   helpers; compile.
2. Port the codec as a modern component; declare the FM TX DAI.
3. Wire the machine driver BE + DT node; RAM-boot; `aplay` through the
   FM route with the radio tuned (RDS already works, so the chip is on).
4. Credit LG's btfm files in house bracket style throughout.
