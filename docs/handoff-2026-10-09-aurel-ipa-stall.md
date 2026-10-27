# Handoff 2026-10-09 — joan IPA RX stall retest, TX-queue patch not proven

Aurel Nymvale, Hermes Agent, xai-oauth/grok-4.7. 2026-10-09, America/Los_Angeles.
Supersedes the 19:15 phone state in `docs/handoff-2026-10-07-ember-r60.md` for the
cellular RX stall only. r60, the qrtr HELLO ban, and the pushed set from that
handoff are unchanged. This is an FYI for Ember, not an assignment.

## TL;DR

- The boot-time RX stall is still open. It did not appear in four later boots.
- "A modem restart restores data" is withdrawn. One restart did not restore
  downlink. A later stop, by name, stuck in `ipa_table_hash_flush()` and then
  ModemManager marked the modem invalid.
- `remoteproc` numbers swap between boots. Stop the modem by sysfs name
  `4080000.remoteproc`, never by index. Stopping `remoteproc1` once stopped the
  ADSP and dropped the sound card.
- An upstream TX-queue patch is applied on a bench-only branch. Four boots with
  it passed data. That does not prove it cures the stall. Not merged, not pushed.
- Do not write a timeout into `gsi_trans_commit_wait()`. That wait is shared.
  Timing it out can free a transaction the hardware still owns.

## Phone right now (11:32)

- US998 on nest USB, pmOS r60 RAM-booted at 11:29. Gadget `172.16.42.1`.
- Data was up on that boot: DNS ping to `2001:4860:4860::8888` 2/2, ~57 ms.
  RX moved 17 → 19 packets.
- Stock `ipa.ko.zst` is back on the SD. sha256
  `78f647350a68cd14335dd7b1e9cd167633da4d4a083a4b6c60cb12ea0d592c35`.
  Backup `/root/ipa-r60-stock.ko.zst` matches.
- The running kernel still has the TX-fix module loaded until the next reboot.
  That reboot was not done.
- ModemManager debug drop-in is on the SD:
  `/etc/systemd/system/ModemManager.service.d/qmi-debug.conf`
  (`--test-quick-suspend-resume --log-level=DEBUG --log-file=/var/log/mm-qmi.log`).
  The packaged `quick-suspend-resume.conf` is masked with a symlink to `/dev/null`,
  because that drop-in resets `ExecStart` and was winning the merge.
- Password files were removed from `/tmp` on the phone.

## What was measured

### Stalls, stock r60, before the TX patch

| boot | attach | RX at freeze | DNS ping | notes |
|---|---|---|---|---|
| 06:44 `ebdb445a` | 29.1 s | 11 pkts / 3072 B | lost | first sample |
| 06:49 `4d8130cb` | 38.1 s | 23–25 pkts | lost | kills the "late attach works" correlate |
| 08:01 debug ko | 28.0 s | 1 pkt / 122 B | lost | ch8 enabled, 249 buffers queued, one 134 B RX |
| 10:11 debug ko | 29.1 s | 11 pkts / 3072 B | lost | then the stuck modem stop |
| 10:44 stock | 28.1 s | 5 pkts / 1275 B | lost | debug drop-in had not applied yet |

A good boot at 10:47 (stock module, debug logging finally on) connected at 37 s.
IPv4 `Start Network` failed `ip-version-mismatch` (expected on this IPv6-only SIM).
IPv6 came up on mux id 1, TX endpoint 3, RX endpoint 16. DNS ping 2/2, ~50 ms.
RX reached 30 packets and kept moving. Gateway ICMP failed on both stalled and
good boots, so do not use the gateway ping as the test. Use the DNS ping.

Excerpt saved at nest `/tmp/joan-ipa-stall-20261009/good-boot-qmi.txt`.

### TX-fix module, four boots, no stall

Module sha256 of the zst:
`c1538c4022f0e7eddd1ba81285212226fd46dd776283a01494a5d46b22171466`.
Uncompressed `aef1f2c2380ec03896e1f18bd8155dd40e156aa54a33a291ffe0967d988d6c16`.
Vermagic `7.2.0-rc2 SMP preempt mod_unload aarch64`. `.BTF` size `0x11394`.

| boot | DNS ping | RX |
|---|---|---|
| 11:03 | 2/2, ~52 ms | 15 → 29 |
| 11:06 | 2/2, ~57 ms | 17 → 19 |
| 11:21 | 2/2, ~45 ms | 22 → 24 |
| 11:29 | 2/2, ~57 ms | 17 → 19 |

Four passes do not prove an intermittent fix. The rule is still two fresh
stalls that then recover. We have zero of those with this module.

## The stuck modem stop

On the 10:11 boot the modem was `remoteproc1` and the ADSP was `remoteproc0`.
Stop was written to `4080000.remoteproc` by name. Kernel logged:

- `received modem stopping event` at 272.6 s
- `JOANDBG crash-path table_reset begin`
- `JOANDBG crash-path table_reset done`

Nothing after that. No channel-8 stop. No modem offline. State file still
`running` minutes later. The next call is `ipa_table_hash_flush()`, which
allocates one command and blocks in `gsi_trans_commit_wait()`. That wait has
no timeout. There was no "no transaction for hash flush" line, so the
transaction was allocated. The notifier is blocked in the wait.

qrtr then timed out ten times. ModemManager marked the modem invalid. ath10k
failed a hardware restart (`qmi config: -110`) as a casualty. Sound card stayed
up, which confirms the ADSP was not the target.

Do not write start or stop again while that notifier is stuck. A second poke
is how earlier sessions hit the LG "any key to shutdown" screen.

## remoteproc numbering

Numbers swap. Observed both ways today:

- `remoteproc0` = modem, `remoteproc1` = adsp
- `remoteproc0` = adsp, `remoteproc1` = modem

An earlier "modem restart dropped the sound card" note is not proven. That
stop may have been the ADSP. Stop by name.

## Code, local only, not pushed

Kernel worktree `~/vibe-coding-projects/coding/linux-mainline-v30-r60-candidate`,
branch `joan/debug-ipa-rx-stall`:

- `14b30de11d2a` channel-8 enable/stop logs and crash-path table-reset logs.
  Bench only.
- `908893280f0e` TX-queue wake fix. Not our invention.

The TX change is Jorijn van der Graaf's posted patch,
`[PATCH net] net: ipa: fix stalled modem TX queue after runtime resume`,
15 Aug 2026. `Fixes: 688de12f080f ("net: ipa: kill the STARTED IPA power flag")`.
The patch message is marked `Assisted-by: Claude:claude-fable-5`. Alex Elder
reviewed the mechanism on the netdev thread. I have not checked whether it
landed in Linus's tree. r60 does not have it.

What it does: `ipa_modem_wake_queue_work()` calls `pm_runtime_get_sync()`
before `netif_wake_queue()`, so a transmit cannot restart while the device is
still `RPM_RESUMING`, stop the queue again, get `-EINPROGRESS`, and leave the
queue stopped forever. They reproduced it on a Fairphone 6 (SM7635), not a V30.
Our stall logs showed `JOANDBG tx drop` with `ret=0` on the quiet-drop path,
not `NETDEV_TX_BUSY`. So this may be a second bug, not the RX freeze.

Sources:

- https://lkml.iu.edu/2608.1/13715.html
- https://patchew.org/linux/20260815040302.653650-1-jorijnvdgraaf@catcrafts.net/
- https://lists.openwall.net/netdev/2026/08/20/177

## Docs commits, local, ahead 4, not pushed

`lg-v30-port` branch `claude/lucid-dijkstra-bxx3r9`:

- `32ff4f5` 2026-10-09 stall retest, matrix correction
- `3ee310f` debug ko load and the ADSP mis-stop
- `befa4fa` modem stop stuck after table reset
- `5bc78e6` the wait is in the hash flush

Evidence dir: `docs/evidence/2026-10-09-ipa-rx-stall/`.

`git rev-list --count ghpub/claude/lucid-dijkstra-bxx3r9..HEAD` was 4 at
handoff write time. Recompute before pushing. Do not push without Lance.

## What not to do

- Do not ship qrtr `544d85de` ("Send HELLO message on endpoint register").
  It crash-loops the MSM8998 modem. r59 contains it.
- Do not package `joan-adsp-watchdog`. Its README still treats that HELLO
  commit as a fix. r60 already has the safe glink FIFO fix `08f939000789`.
- Do not merge `joan/debug-ipa-rx-stall`.
- Do not stop a remoteproc by index.
- Do not `devmem` IPA registers while IPA is runtime-suspended.
- Do not send `fastboot boot` after the phone has already enumerated. Arm
  first. A late send hangs aboot and lands on the any-key screen.
- Scripted reboots still drop USB after a successful send. The phone then
  comes up on the lockscreen, or falls back to Lineage. Budget for Lance
  being present. `ramboot.sh`'s armed send dies if the tool session times
  out. A user `systemd-run` unit with the log in `/tmp/fb-armed.log` survived.
  Confirm the log says `waiting for any device` before the reboot.

## Next useful step

One stalled boot with `/var/log/mm-qmi.log`, compared to the 10:47 good boot:
DPM open (TX 3 / RX 16), Bind Mux Data Port on mux 1, and the IPv6 Start
Network result. If those match and DNS ping still fails, the bug is below
QMI. If they differ, that difference is the bug. Do not stop the modem on
that boot. The debug drop-in is already staged, so no more SD edits are
needed for the log.

The TX-fix module can stay a candidate until two stalls recover with it.
Four good boots are not that evidence.

## Needs Lance present

- Any further RAM boot. USB drops after a successful armed send.
- Snapshot, rear camera, lit scene, plus colour tuning.
- NFC tag read/write.
- FM radio audio. SoC-hang risk.
- CLAT on another SIM, roaming, hotspot client.
- USB-C display sink. Not ported.
- Overnight battery soak.
- A saved Wi-Fi profile, if post-restart association is to be tested.
  Firmware recovered once today. Association was not tested.

## Decisions still Lance's

- Push the four docs commits.
- Push or drop `908893280f0e`. Do not merge it on this evidence.
- Upstream report for qrtr `544d85de`.
- pmOS CLAT draft at nest
  `~/.ember/workspace/joan-clat-2026-10-07/pmos-upstream-issue-DRAFT.md`.
- Speed bins 0/1. Untestable on this bin-2 phone.
- Whether `fm-radio` and Chatty/Snapshot become hard dependencies.
