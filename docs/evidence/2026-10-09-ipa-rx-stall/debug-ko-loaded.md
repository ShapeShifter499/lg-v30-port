# debug ipa.ko loaded, then the wrong remoteproc was stopped (2026-10-09)

Aurel Nymvale, Hermes Agent, xai-oauth/grok-4.7. Bench only. Not merged.

## Module

`joan/debug-ipa-rx-stall` `14b30de11d2a` (local, not pushed).
Uncompressed sha256 `9272012d7655c187f65d953999f678521c3321c912c72a0407306a80bd288166`.
vermagic `7.2.0-rc2 SMP preempt mod_unload aarch64`. `.BTF` section size `0x11394`.

The first build (`e30a0b43…`) had an empty `.BTF` and the kernel rejected it
(`failed to validate module [ipa] BTF: -22`). Stock was restored and RAM-booted
before this attempt. Do not install a module whose `.BTF` size is `0x00f473`
from that first link; that size was a stub.

## What the loaded module showed (boot 08:01)

- `qmi_ready` walked `modem_ready=0 uc_ready=0` then `uc_ready=1` then both 1,
  `initial_boot=1`, `indication_sent=0`, then `ipa_modem_start` from state 0.
- `ipa_open` at 30.1 s. `JOANDBG ch8 enable ep=16 toward_ipa=0`.
- Replenish queued 249, 15 doorbells. One RX of 134 bytes. Then nothing useful.
- Attach at 28.0 s. Gateway ping 0/2. RX frozen at 1 packet / 122 bytes.
- Two later RX of 12 bytes at 103–104 s did not move the mux counter. Not a recovery.

## The restart was the ADSP, not the modem

`remoteproc` numbers swap between boots. This boot:

- `remoteproc0` = `4080000.remoteproc` (modem), stayed `running`
- `remoteproc1` = `adsp`

`echo stop` was written to `remoteproc1`. Kernel logged
`remoteproc remoteproc1: stopped remote processor adsp`, then it was started
again and came up. No `received modem stopping event`. No `JOANDBG ch8 stop`.
No crash-path table reset. The IPA notifier is registered on `mpss`, so an
ADSP stop cannot run it.

`/proc/asound/cards` was `no soundcards` after that ADSP cycle. The earlier
"modem restart dropped the sound card" note is not proven. That stop may
have been the ADSP too, if the numbering had swapped. Do not treat remoteproc
numbers as stable. Stop by `name`, never by index.

## Left on the phone

Stock `ipa.ko.zst` restored on the SD (sha256
`78f647350a68cd14335dd7b1e9cd167633da4d4a083a4b6c60cb12ea0d592c35`).
The running kernel still has the debug module loaded until the next reboot.
That reboot was not done. Password files removed.
