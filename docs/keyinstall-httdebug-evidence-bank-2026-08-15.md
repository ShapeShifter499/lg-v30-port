# WCN3990 HTT key-install diagnostic evidence bank, 2026-08-15

Written-by: Hermes Agent:moa/deep-flash
Date: 2026-08-15

## Scope and result

One RAM-only boot used the AP source image associated with intended/current
baseline `519646f01` and added only `ath10k_core.debug_mask=0x8`. Its runtime
release was `7.2.0-rc2-gd05e70c5e484-dirty`, so exact build-source provenance
is inherited from the source image and remains unproven. Exactly one nym-fang
association was performed against hostapd on joan. The association-time
pairwise key received a matching, prompt `SEC_IND` and succeeded. No matching
indication was observed for the later pairwise `DEL_KEY` during controlled
client teardown, which timed out. This is lost from the host's perspective;
whether firmware generated a delete acknowledgement remains open. Full
interpretation and next steps are in
`ember-handoff-2026-08-15-wifi-ap-and-key-install.md`.

No phone partition was flashed or erased. The phone was recovered to installed
LineageOS and independently verified over ADB as serial `LGUS9986e606d55`,
`sys.boot_completed=1`, Android 13 / LG-US998; the pmOS USB interface and ping
path were absent afterward.

## Durable locations

The raw artifacts are intentionally ignored by git:

```
out/audit-20260815/keyinstall-httdebug-519646f01/
```

The exact device-host source was also retained at:

```
nym-nest-family:~/joan-images/evidence/keyinstall-httdebug-20260815T0045Z/
```

The portable local manifest covers 35 files and verifies successfully:

```
out/audit-20260815/keyinstall-httdebug-519646f01/EVIDENCE-MANIFEST.sha256
SHA-256: 967b24979d4ae3edaf3f8cee05aef8bf6637bfb783b47cdf3e4e436e2dbdbcaa
```

The device-generated `device/SHA256SUMS` uses absolute
`/tmp/keyinstall-evidence/...` paths. Its first host-side `sha256sum -c` failed
only because those source paths do not exist on the host. A path-independent
Python verification recomputed all seven copied device artifacts and matched
every digest; the portable run manifest then re-verified all 35 files,
including unpacked source/candidate components and independent Android recovery
verification.

## Key identities and hashes

| artifact | SHA-256 |
|---|---|
| original AP-mode source image | `bb7362e981cc3686648557c169732abce55ba969e0347a3a7c71fba8bb0630cf` |
| HTT-debug RAM-boot candidate | `3dfad94194d3bedef972eed11c7c9a37aa1cee3427042682605b03479171b19f` |
| hash-bound one-shot runner | `ead67ac5055c3aff0d77a849a4b3f7c32280ec128d56821b63fef30d3282e676` |
| capture/seal script | `9b248ce5db7502ec0c7b0d661431d09982156cb8d99e23857730bc72a8892800` |
| phone `dmesg-full.log` | `488ea4f3e967c12e4cd16c1318ed4694fa185951e610e89ee7a2db05385cf6f8` |
| hostapd debug log | `83f7d9c3a2c0482189281fb14dfbcf64721154589d139fc08b7888e5f58d5251` |
| correlated key timeline | `613a4b9ab79c2db768ec073dcae3c47a1cb23252ee1cc52ae311c5143d0d565c` |
| nym-fang client debug log | `d713f5efde9ddd54f2ac8db3800094c409cbb2cb7f7031ad14dd5ed0859fe12e` |
| recovery log | `47e8c3ce05486c010f45b0a01bad5c08b092b63ce77306a8f7938ac378f6afb8` |
| Android recovery verification | `6ef3f0153fcc1df41b07aa28ca03305fadf1a94d4c3e44ee90c4797447201a33` |

The logs redact PSK/passphrase bytes as `[REMOVED]`; raw AP/client configuration
files containing the credential were not copied into or indexed by this bank.

## Decisive timeline (phone monotonic seconds)

```
731.474514  client e4:5f:01:07:fc:f3 mapped to HTT peer 30
731.568572  hostapd pairwise NEW_KEY
731.587118  hostapd AP-STA-CONNECTED
731.589262  SEC_IND peer_id 30 unicast 1 type 6 (matching, ~21 ms after NEW_KEY)
743.699674  client-originated disassociation, reason 8
743.709249  hostapd pairwise DEL_KEY begins
746.976115  ath10k generic "failed to install key ... -110"
936.982182  evidence seal; no later SEC_IND
```

Pre-association and sealed counts were respectively:

| counter | before | sealed |
|---|---:|---:|
| key timeout | 0 | 1 |
| SEC_IND | 3 | 5 |
| WLAN stream-0x1900 SMMU fault | 5 | 5 |
| AMSDU extraction failure | 0 | 0 |
| modem fatal / crash | 0 / 0 | 0 / 0 |

The extra two `SEC_IND` events were the AP group-key indication and the matching
peer-30 pairwise-install indication. No matching teardown indication was
observed by the host.

## Recovery-script note

The existing recovery helper returned exit 1 after successfully issuing the
pmOS reboot because `set -euo pipefail` treated an expected zero-match `lsusb`
probe as fatal before its polling loop could observe Android. This is a helper
false negative, not a recovery failure. Android recovery was verified directly
as described above; no second reboot or recovery attempt was made.