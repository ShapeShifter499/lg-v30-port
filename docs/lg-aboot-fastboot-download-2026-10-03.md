# LG aboot fastboot: what "Requested download size is more than max allowed" means (2026-10-03)

Written-by: Ember (Claude-Code:claude-opus-5-5)

From 09:52 on 2026-10-03 every `fastboot boot` of a 31 MB image was refused, although the
same size went through at 09:47. Decompiling LG's LinuxLoader from the stock US99830b ABL
(Ghidra headless; work dir skyforge `/data/buildcache/abl-re`, `all.c` = every function):

- `CmdDownload` (0x38214): `size = hex(arg)`; `0 < size <= 0x20000000` -> reply `DATA`;
  otherwise the generic failure, whose text is **"Requested download size is more than max
  allowed"** — sent for size 0 (unparseable) as well as for > 512 MB.
- Fastboot init (0x368f8) allocates a 1 GiB buffer on UFS (512 MB on NAND) and publishes
  `kernel`, `max-download-size`, `product`, `serialno`, `secure` together.
- The dispatcher (0x36384) matches commands by prefix against a registered list; LG adds a
  battery-voltage gate (after `getvar:partition-type`) and a "last flash failed" gate.

Observed in the bad state: `getvar product` answering three different ways in a row,
`max-download-size` sometimes `536870912` and sometimes "unknown command" / "not found",
bulk-write timeouts, `fastboot reboot`/`continue` refused, sessions ending on LG's "any key to
shutdown" screen. Ruled out: microSD, battery (100 %), lock state (orange), PMIC PON spare
(0x88f = 0), cold vs warm entry. Conclusion: corrupted fastboot traffic on the bench USB path
(nest EHCI rate-matching hub, port 1-1.5), not a bootloader setting.

Bench rules that follow:
- Never pipe fastboot through `tail -1` — the real error is on the first line.
- Probe `getvar max-download-size` before sending; never `reboot-bootloader`/`reboot` from a
  confused fastboot (that is what ends at "any key to shutdown").
- `tools/bench/ramboot.sh` enforces both.
