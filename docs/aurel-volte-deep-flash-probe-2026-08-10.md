# LG V30 mainline VoLTE deep-flash probe — 2026-08-10

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:moa/deep-flash
Date: 2026-08-10
State: feasibility/reconnaissance only; no phone or rootfs changes

## MOA provenance

- Aggregator/acting: `openai-codex:gpt-5.6-sol` (`reasoning=high`)
- Reference: `zai:glm-5.2` (`reasoning=high`)
- Reference: `minimax:MiniMax-M3` (`reasoning=high`)
- Reference: `deepseek:deepseek-v4-flash` (`reasoning=high`)

## Verdict

**Feasible, but not a toggle or single-package fix.** Joan has enough proven
modem/IPA hardware support and a complete downstream voice implementation to
make this a credible porting project. Mainline joan is still missing three
independent layers before VoLTE can work end to end:

1. modem discovery/control in ModemManager on the known-good matching-module
   boot;
2. Qualcomm IMS data-session service (`81voltd` or equivalent);
3. q6voice call-audio support plus the joan audio card/routing topology.

Carrier IMS provisioning/configuration is a fourth, separately variable gate.
A carrier failure must not be mistaken for a kernel or audio failure.

## What joan already proves locally

The last matching-module modem bring-up proved:

- MPSS boots and reaches `running`;
- rmtfs exposes the modem's full service set (45 QMI services rather than 3);
- QRTR/IPCRTR is present;
- IPA setup completes and creates `rmnet_ipa0`;
- battery and the rest of the integrated baseline remain healthy.

The remaining modem-control symptom was `mmcli -L` returning no modem. The
working modem handoff recorded that ModemManager had QRTR enabled and loaded its
plugins, while joan exposed no `/sys/class/wwan` device. ModemManager itself can
support modem-control nodes directly over QRTR sockets, not only WWAN character
devices, so the next step is a debug run on the exact matching-module modem
baseline rather than assuming `/sys/class/wwan` is strictly required.[3]

The current GPU diagnostic RAM boot was intentionally built without installing
a matching module tree. Its empty `qrtr-lookup`, stopped ModemManager, and absent
ALSA card are therefore not valid regressions. They only confirmed the rootfs
currently has ModemManager/libqrtr/qrtr installed, while `81voltd`, `q6voiced`,
and oFono are absent.

## Layer 1: ModemManager discovery must come first

`81voltd` drives bearers through ModemManager's D-Bus API, so it cannot solve a
modem that ModemManager does not expose. ModemManager documents Qualcomm modem
control through QRTR nodes using AF_QIPCRTR sockets.[3]

First controlled milestone:

1. boot the exact battery-working kernel with its matching module tree and the
   known-good modem firmware/rmtfs setup;
2. verify the full QRTR service table and save it;
3. start ModemManager in debug mode;
4. capture QRTR-node discovery, plugin selection, and rejection reason;
5. repair only that binding/discovery problem;
6. prove SIM, registration, SMS, and a normal data bearer before adding IMS.

Do not debug VoLTE on the current no-matching-modules GPU image.

## Layer 2: IMS data service

`81voltd` is a FOSS server-side implementation of Qualcomm's QMI IMS Data
service over QRTR. It accepts modem requests to start/stop the IMS bearer and
uses ModemManager to create the connection.[2] Its documented critical request
is IMSD service 770/version 1 message `0x20`, which carries the APN/profile/IP
family and asks the AP to start the network. Message `0x21` stops it.[2]

This is the likely userspace component for joan after ModemManager works. It is
not universally sufficient: postmarketOS reports it working on some SDM845
phones/carriers while failing on a more complicated carrier configuration.[4]

Second milestone:

1. install/package `81voltd` only after ModemManager sees joan;
2. observe whether the modem advertises/requests IMSD service 770;
3. capture the requested APN/profile/IP family;
4. verify an IMS bearer and assigned address;
5. preserve all QMI/QRTR traces without writing modem NV.

## Layer 3: call signaling versus call audio

A successful IMS bearer and dial/hangup signaling still do not produce handset
audio. Qualcomm Android-phone ports use a q6voice kernel driver plus
`q6voiced`; postmarketOS describes these patches as currently carried by many
close-to-mainline Qualcomm kernels and not yet upstreamable, with a funded 2026
redesign underway.[1]

Joan's current mainline DTS has no enabled sound-card/audio topology, even
though the kernel config builds generic QDSP6/APR components as modules. The LG
downstream tree is a strong hardware oracle:

- `CONFIG_SND_SOC_MSM8998=y` in joan defconfigs;
- joan sound DTS includes `msm-pcm-voice`, `msm-voip-dsp`, Q6 DAIs, SLIMbus,
  Tavil codec, and ES9218;
- downstream `q6voice.c` supports CVD 0.0, 2.1, 2.2, and 2.3;
- downstream includes voice PCM, routing, APR CVS/CVP/MVM sessions, AMR/AMR-WB,
  HD voice, DTMF, and calibration paths.

This proves the hardware/firmware path exists, but the downstream stack is very
large and cannot be copied wholesale as a clean mainline solution. The current
postmarketOS q6voice redesign may materially reduce the porting burden if it
lands; until then joan would need a close-to-mainline q6voice patch series and
an MSM8998/joan hardware enablement layer.[1]

Third milestone:

1. establish normal playback/capture and the joan sound card first;
2. identify the exact ADSP firmware/CVD response and voice service endpoints;
3. adapt the current q6voice patchset to MSM8998 CVD 2.3;
4. map handset earpiece, speaker, primary mic, headset, and Bluetooth routes;
5. supply safe calibration from the existing firmware/partitions without
   modifying protected modem/audio NV;
6. prove call audio after call signaling works.

## Layer 4: carrier provisioning

VoLTE is carrier-policy sensitive. The OnePlus 6 postmarketOS investigation
notes that modem low-level configuration must be selected/uploaded per provider
and that additional QMI IMS messages may need reverse engineering.[5]
`81voltd` also has observed carrier-dependent success.[4]

For Lance's eventual test, record SIM carrier/MVNO, IMS APN, LTE registration,
VoPS indication, IMS registration, and emergency-call behavior separately.
Never use emergency services for testing. Start with a harmless incoming call
or a second owned line only after registration and audio routing are proven.

## Recommended project order

1. **ModemManager discovery card** — exact matching-module baseline, debug why
   the 45-service QRTR modem is not created.
2. **Basic telephony card** — SIM, registration, SMS, normal data bearer.
3. **IMS data card** — package/run `81voltd`, capture IMSD requests, prove IMS
   bearer.
4. **Mainline audio card** — ordinary playback/capture, Tavil/SLIMbus/joan
   topology.
5. **q6voice card** — MSM8998 CVD 2.3 voice sessions and routing.
6. **Carrier qualification matrix** — IMS registration and call tests per
   carrier/configuration.

## Effort/risk estimate

- ModemManager discovery: **small-to-medium**, likely userspace matching or
  service-enumeration work, but must be reproduced first.
- IMS bearer with `81voltd`: **medium** after ModemManager works; carrier risk.
- Mainline joan sound card: **large**; currently absent.
- q6voice/CVD 2.3: **large/research-grade** unless the funded upstream redesign
  lands with MSM8998 support.
- End-to-end VoLTE qualification: **large and carrier-specific**.

No new blobs, packages, modem writes, APNs, calls, or public actions were made
for this probe.

## Sources

[1] https://postmarketos.org/blog/2026/05/08/q6voice-project
[2] https://gitlab.postmarketos.org/modem/81voltd/-/tree/main
[3] https://modemmanager.org/docs/modemmanager/wwan-device-types
[4] https://gitlab.com/postmarketOS/pmaports/-/merge_requests/5387
[5] https://gitlab.com/postmarketOS/pmaports/-/issues/1878
