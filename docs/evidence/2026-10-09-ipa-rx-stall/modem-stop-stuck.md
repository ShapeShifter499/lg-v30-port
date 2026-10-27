# modem stop stuck after table reset (2026-10-09 10:15, Aurel)

Debug ipa.ko (BTF rebuild, sha256 of zst
`87aed71314aefc9b7dc928adb5646e1e277feee6130ce945605e9a6dc580eddf`)
loaded on the 10:11 RAM boot. Armed fastboot was running before the
Lineage reboot. USB dropped after the send reported success; the phone
was on the pmOS lockscreen and the gadget came up at 10:15.

## Stall

Attach 29.1 s, connected 31.1 s. Channel 8 enabled at 31.1 s, endpoint 16.
RX froze at 11 packets / 3072 bytes. Gateway ping 0/2. Same shape as the
earlier stalls.

## Stop by name

This boot the numbers had swapped again:

- remoteproc0 = adsp, stayed running
- remoteproc1 = 4080000.remoteproc (modem)

Stop was written to the modem by name, not by index. Kernel logged
`received modem stopping event` at 272.6 s, then:

    JOANDBG crash-path table_reset begin
    JOANDBG crash-path table_reset done

Nothing after that. No `JOANDBG ch8 stop`. No `modem offline`. No
`GSI command 2 timed out`. No `crash-path modem_stop`. The modem state
file still read `running` two minutes later. Sound card stayed up,
which confirms the ADSP was not the target.

The next call after table reset in `ipa_modem_crashed()` is
`ipa_table_hash_flush()`. That is where the notifier is stuck. The
sysfs stop write did not return. Do not write start or stop again on
this boot. A second stop while the notifier holds the path is how the
earlier session landed on the any-key screen.

## Left on disk

Stock ipa.ko.zst restored (sha256
`78f647350a68cd14335dd7b1e9cd167633da4d4a083a4b6c60cb12ea0d592c35`).
Running kernel still has the debug module until the next reboot.
That reboot was not done. Password files removed.

## Still stuck at 597 s (follow-up, no second write)

Modem state file still `running`. ADSP still `running`. Sound card still
present. No `JOANDBG ch8 stop`, no `crash-path modem_stop`, no
`no transaction for hash flush`.

`ipa_table_reset()` returned, so its `gsi_trans_commit_wait()` calls
completed. The next call is `ipa_table_hash_flush()`, which allocates
one command transaction and waits in `gsi_trans_commit_wait()`. That
wait has no timeout. The missing `no transaction for hash flush` line
means the transaction was allocated. The notifier is blocked in the
wait, not in the allocator.

ath10k then timed out a WMI scan and failed a hardware restart
(`failed to send qmi config: -110`, mac80211 warnings at 377 s). That
is a casualty of the stuck modem stop, not a separate IPA fault.
Wi-Fi was not associated.

No start, no second stop, no reboot. Stock module remains on disk.
