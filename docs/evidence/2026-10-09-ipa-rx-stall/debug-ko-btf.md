# debug ipa.ko did not load (2026-10-09, Aurel, Hermes:grok-4.7)

Bench-only branch `joan/debug-ipa-rx-stall` `14b30de11d2a` adds channel-8
enable/stop logs and crash-path table-reset / mem-zero logs. Not pushed.

Built at `/data/buildcache/aurel-ipa-ko-20261009/drivers/net/ipa/ipa.ko`
with `LOCALVERSION=` so vermagic is `7.2.0-rc2 SMP preempt mod_unload aarch64`,
matching the running r60 module. sha256 of the uncompressed ko:
`e30a0b43ee2136b5d0304f40cb36b527fae44c587b4dc0f4ac736ac521e61943`.

Installed as `ipa.ko.zst` and RAM-booted r60 at 07:55. Kernel refused it:

    failed to validate module [ipa] BTF: -22

IPA never initialized. ModemManager found no modem. Stock module restored
from `/root/ipa-r60-stock.ko.zst` (sha256
`78f647350a68cd14335dd7b1e9cd167633da4d4a083a4b6c60cb12ea0d592c35`) and
RAM-booted again at 07:57. That boot logged `IPA driver initialized` and
`IPA driver setup completed successfully`, and ModemManager reached
`connected` / `attached` by 45 s.

Cause: the out-of-tree module was built without BTF (`CONFIG_DEBUG_INFO_BTF`
was not in the seeded config the way the packaged module was). A retry
needs pahole and BTF in the module, then another armed RAM boot. Do not
leave the debug module installed.
