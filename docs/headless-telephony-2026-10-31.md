# External US998 headless voice and SMS contribution

Source: [headless bundle](../device/headless/README.md).
This is an external contributor's US998 and does not certify the maintainer's
phone or the current kernel. The tested local release was
`7.2.0-rc2-v30-r30`; default-boot integration and SMS were accepted on
2026-10-31 (Asia/Shanghai), on China Unicom.

| Scope | Observation | Limit |
|---|---|---|
| Incoming voice | About 60 seconds in a RAM session and again after ordinary default boot; owner confirmed clear speech both directions and landscape TTY | Local stack only, no current-kernel boot |
| Audio cleanup | Each call restored the saved mixers and closed PCM devices; second-call and failure rollback covered by unit tests | Long calls, suspend and headset switching unqualified |
| SMS send | One short Chinese UCS2 SMS; owner confirmed complete receipt | submitted alone was not counted as receipt |
| SMS receive | One short Chinese SMS; CLI read matched the expected body | Real multipart/binary SMS unqualified |
| SMS reboot persistence | One ordinary reboot; same incoming record/body retained without duplicate, outgoing submission not repeated | Does not prove long-term retention |
| Post-reboot integration | Services resumed, cellular-bound DNS/HTTPS and IMS registration passed; pure TTY landscape and Bluetooth off retained | No extra voice test during SMS acceptance |

No real call, SMS, reboot or partition write was performed while preparing this
contribution. All prior one-shot communications allowances are consumed/closed.
The reference does not contain an automated live acceptance runner.

## Kernel disposition

Base for the separate kernel work is
`dc9c6692dbfba9c114eb116f48be9cf3e283ac0f` on `joan/latest-clean-test`.
The affected fuel-gauge, charger, IPA QMI and GCC objects were built on native
Alpine aarch64 using an adapted local config (`olddefconfig`). This is target
object compilation, not a full kernel/image build or device qualification.

- Fuel gauge: query charger status before its first notification, correct the
  already-converted current sign, and avoid overwriting UNKNOWN on a failed read.
- Charger: expose charge_behaviour auto/inhibit-charge without suspending USB
  input; preserve the existing STATUS behavior.
- IPA: receive variable CONFIG/FILTER server requests up to the u16 QMI payload
  bound; do not import local diagnostic logging or qmi_hold workarounds.
- GCC: adapt Dmitry Baryshkov's October 19 GPU/MMSS always-on patches via the
  existing qcom_cc_driver_data CBCR mechanism. These are derived fixes, not
  newly authored clock algorithms. Original messages:
  [GPU](https://lore.kernel.org/all/20261019-msm8998-fix-clocks-v1-1-370949e4d8a0@oss.qualcomm.com/),
  [MMSS](https://lore.kernel.org/all/20261019-msm8998-fix-clocks-v1-2-370949e4d8a0@oss.qualcomm.com/).

IPA system-header-table, GLINK endpoint-destroy deadlock, WCD934x ADC MUX8 and
board MIC BIAS/MCLK routes already exist at this base and are not duplicated.
ICC frequency holds, codec snapshots/holds and GCC/IPA diagnostics stay local.

## imsd disposition

The separate Forgejo candidate is based on
`2b5de7a60b3d9ecedab5fa34da40b2d3c8b26cab`: opt-in six-tuple LG Security-Client
offer with exact-common selection/resume validation; every Via preserved in
200 responses; bounded optional metadata tracing; fixed-media offerless incoming
re-INVITE answered with an SDP offer and a matching ACK answer/timeout.
Media renegotiation remains unsupported and receives 488.

Eight unit suites and all five products compiled with Alpine clang 23.1.4,
C++26/libc++/lld and ARMv8-A. This manual module build does not claim a Crafter
lint pass. A Forgejo account and the project's GPG-signing requirements are
still prerequisites for submitting that series to its own upstream.

Only sanitized summaries and source hashes are public. Raw phone evidence,
subscriber data and private backup receipts remain excluded. This summary
is contributor-reported evidence, not a public durable seal of those captures.

Assisted-by: Codex:OpenAI/GPT-6
Date: 2026-10-31
