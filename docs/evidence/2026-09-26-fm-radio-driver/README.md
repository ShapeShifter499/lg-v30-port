# 2026-09-26: FM radio driver (/dev/radio0) on the LG V30

Kernel `joan/bootlog-fixes` (ShapeShifter499/linux-lg-v30-joan):

| Commit | What |
|---|---|
| 5344583b8215 | binding: `qcom,fm-receiver` on qcom,wcn3990-bt |
| 4a04a4310739 | hci_qca: FM packets (H4 0x11 out, 0x14 in), `qca_fm_send()`, auxiliary device `hci_uart.fm.N`, setup generation counter |
| 621a3778bf10 | `drivers/media/radio/radio-qca-fm.c` (`CONFIG_RADIO_QCA_FM`) |
| 4aef1e1c44eb | joan DT: `qcom,fm-receiver` |

Needs `CONFIG_MEDIA_RADIO_SUPPORT=y`, `CONFIG_RADIO_ADAPTERS=m`,
`CONFIG_RADIO_QCA_FM=m` (not yet in the pmaports config) and Bluetooth
powered on (FM shares the controller's power).

Tested on bench kernel bl17 (US998):

- `fmtest-no-antenna.txt`: no headphones. Tune 90.3 MHz (38-40 %
  signal, mono), mute, Bluetooth off (EIO) and on (receiver restored).
  Seeks found nothing at this level and returned ENODATA.
- `sweep-and-seek-headphones.txt`: wired headphones as antenna. 15
  channels at 44-72 %, strongest 103.5 MHz, most stereo; six wrapping
  seeks up from 87.9 MHz stepped 88.9, 90.9, 92.5, 94.7, 96.1, 96.9.
- `rds-events-103.5.txt`: firmware events over 25 s with every RDS group
  enabled (bench build, `dyndbg` on): 109 raw groups (0x08), 4
  programme-service (0x09), 1 radio-text (0x0a). Raw group layout: a
  count byte, blocks A-D least significant byte first, four status
  bytes (low 3 bits read A=1 B=2 C=3 D=5; the rest unknown).
- `rds-ctl-103.5.txt`: `rds-ctl --read-rds --print-block` on
  /dev/radio0: PI 0x345A (KNTY in RBDS), PTY 10 (rds-ctl prints the RDS
  name "Pop Music"; in the RBDS table 10 is Country), scrolling PS
  ("KNTY Zac", " Brown B", "and W/ J"). A few corrupted PI codes reach
  userspace; the decoder outvotes them.
- v4l2-compliance: 48 tests, 0 failures, 0 warnings.

Seek note: right after a seek, "service available" in the station
parameters reads 0 even for the station just found, and a seek that
finds nothing wraps back to where it started. The driver therefore
judges a seek by whether the frequency moved.

Station detection is by the firmware's SINR threshold; without an
antenna even the strongest station sits at SINR 8-12 and is found only
sometimes. No threshold control is exposed yet (Qualcomm's HAL sets it
through `SET_CH_DET_THRESHOLD`, 0x13/0x17).

Not done: FM audio (SLIMbus from the WCN3990), a default radio app.
