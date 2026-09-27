# 2026-09-26 — FM receiver works on mainline (control path, no audio yet)

LG V30 US998, bench kernel bl15 (joan/bootlog-fixes plus the bench-only
`tools/bench/fmprobe-hci_qca.patch`, which lets debugfs send Qualcomm FM
command packets, H4 type 0x11, over the Bluetooth UART and logs FM event
packets, type 0x14). No headphones plugged in, so no FM antenna.

Protocol: the WCN3990's "helium" FM uses the same HCI command set as
Qualcomm's older "iris" FM (OGF 0x13 receive, 0x15 common, 0x16 status;
the 47 iris OCFs are identical in helium, which adds two). References:
radio-iris.c/radio-iris.h (GPL-2.0, The Linux Foundation, via
LineageOS/android_kernel_qcom_msm8996) and the helium HAL
(LineageOS/android_vendor_qcom_opensource_fm-commonsys).

| Step | Command | Result |
|---|---|---|
| Receiver on | `01 4c` (0x13/0x01) | complete, status 0; returns the default config (87.5-108 MHz) |
| US config | `04 4c` (0x13/0x04): 75 us, 200 kHz, RBDS | complete, status 0 |
| Sweep 87.9-107.9 MHz, 200 kHz (`fmscan.sh`) | `01 54` tune (0x15/0x01) per channel | 101 tune-status events. Only **90.3 MHz** reports service available: RSSI -91 dBm, SINR +4, band median -103 dBm |
| Repeat sweep and dwell (`fmcheck.sh`) | same | 90.3 MHz again the only station; six dwell reads -91 dBm, SINR +7..+9 |
| RDS (`fmrds.sh`) | event mask, RDS group mask and processing on, tune 90.3 | service-available event, **RDS sync lock** events (8), one raw RDS group. Station name and radio text requests return empty at this signal level |

Conclusion: the tuner receives and synchronises to a real broadcast with
RDS through mainline's Bluetooth UART. What is missing is a kernel radio
driver (V4L2 `/dev/radio0`) instead of the debugfs hook, and the audio
path (second SLIMbus, the WCN3990 BT/FM SLIMbus codec, DSP routing; Deck
#163). With wired headphones as the antenna, the station name should
decode.
