# LG V30 (joan): firmware, packages and kernel config for mainline pmOS

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-08

Everything here is device-verified on joan (US998) unless marked
otherwise. Every firmware file comes off the phone's own Android
install — nothing is redistributable, and everyone must extract their
own.

## 1. Firmware to extract from the stock system

Boot LineageOS (or stock), `adb root`, and pull. Sources and
destinations:

| what | pull from | install to |
|---|---|---|
| modem | `/vendor/firmware_mnt/image/mba.mbn` | `/lib/firmware/qcom/msm8998/joan/` |
| modem | `/vendor/firmware_mnt/image/modem.mdt` | `/lib/firmware/qcom/msm8998/joan/` |
| modem | `/vendor/firmware_mnt/image/modem.b??` (27 files) | `/lib/firmware/qcom/msm8998/joan/` |
| Bluetooth | `/vendor/firmware/crbtfw21.tlv` | `/lib/firmware/qca/` |
| Bluetooth | `/vendor/firmware/crnv21.bin` | `/lib/firmware/qca/` |
| WLAN | `/system/vendor/firmware_mnt/image/wlanmdsp.mbn` | `/lib/firmware/` |
| WLAN board | `/vendor/firmware_mnt/image/bdwlan.bin` | `/lib/firmware/ath10k/WCN3990/hw1.0/board.bin` |
| IPA | `/vendor/firmware_mnt/image/ipa_fws.mdt` + `ipa_fws.b??` | `/lib/firmware/` |

Known-good hashes on a US998 (yours should match if you are on the same
firmware; a mismatch is informational, not necessarily wrong):

    crnv21.bin     43f429abcf72c6a0e93e6de2875a174369dc83002ab539826c40da30677337e9
    crbtfw21.tlv   8d587968cd90fb2c4bf94cd06921e9979015172b49ac3a8741947dd37675f2c5
    wlanmdsp.mbn   88fee31661c697a12395613ba135908395e88d7d3ede39ecc18336a28b1d2bb4

**Verify the modem set is complete before booting.** `modem.mdt` is an
ELF whose program headers say exactly which `.bXX` files must exist:

    30 program headers, 3 with filesz == 0 (no file expected: 15, 19, 29)
    -> 27 modem.bXX files, sizes matching each header's p_filesz

A short or mismatched set fails authentication with nothing useful in
dmesg. Parsing the headers takes a few lines of Python and is worth it.

**The modem's load address is not negotiable.** `modem.mdt`'s loadable
segments land at `0x8b400000-0x92b00000` — LG's `modem_mem`, and 24 MB
away from the generic msm8998.dtsi layout. The DT must match or the MBA
refuses the image. See `ember-handoff-2026-08-08-modem-layer1-and-integration.md`.

## 2. pmOS packages

    apk add qrtr        # qrtr-lookup, for inspecting the QMI bus
    apk add rmtfs       # remote filesystem service the modem needs

Notes that cost time to learn:

- **The QRTR name server is in the kernel**, not userspace — `net/qrtr/ns.c`
  since 5.7. You do not need a `qrtr-ns` daemon and the Alpine `qrtr`
  package does not ship one. Install `qrtr` only for `qrtr-lookup`.
- `rmtfs` pulls in `rmtfs-udev` and `rmtfs-openrc`. If the device's
  uplink cannot sustain downloads (joan's USB gadget link often can't
  — `apk update` succeeds, package downloads fail with "Socket not
  connected"), fetch the `.apk` files on the host and install them all
  together:

      apk add --allow-untrusted /tmp/rmtfs-udev-*.apk \
                                /tmp/rmtfs-openrc-*.apk \
                                /tmp/rmtfs-*.apk

  Passing only some of them makes apk go to the network for the rest.
- **`rmtfs` is not optional — the modem does not finish initialising
  without it.** Before running it the modem advertised 3 QMI services;
  with it running the full suite appears (Voice, Network Access,
  Wireless Data, Wireless Messaging, UIM, Card Application Toolkit,
  Location, IPA control, ~30 in total). If your modem boots but has
  almost no services, this is why.

  Correct invocation, from the source's own `getopt(argc, argv, "o:S:Prsv")`:

      rmtfs -P -r -s

  `-P` use raw EFS partitions, `-r` avoid writing to storage, `-s` sync
  for the mss rproc instance. **Do not pass `-o <dir>`** unless you mean
  it — it redirects storage to files in that directory and you will see
  `failed to open '<dir>/modemst1' (requested '/boot/modem_fs1')`.

  `rmtfs` mediates modem access to NV partitions on **internal storage**
  (`modemst1`, `modemst2`, `fsg`, `fsc` under `/dev/disk/by-partlabel/`)
  — calibration and provisioning data shared with your Android install.
  Use `-r` unless you have a reason not to.

## 3. Kernel config: what must be built in, not modular

This is the single biggest source of wasted boots. **joan is RAM-booted
via `fastboot boot`, so `/lib/modules/<release>` on the SD rootfs never
matches the running kernel unless you rebuild and reinstall modules for
that exact `git describe` string.** Anything needed during boot must be
`=y`.

Each of these cost at least one boot to discover:

| symbol | why | symptom when `=m` |
|---|---|---|
| `QCOM_Q6V5_MSS` | modem remoteproc | no `remoteproc0` |
| `QRTR`, `QRTR_SMD` | QMI transport | `failed to initialize qmi handle`, probe defers |
| `QCOM_SYSMON`, `QCOM_Q6V5_COMMON`, `QCOM_RPROC_COMMON` | modem support | as above |
| `QCOM_SPMI_RRADC` | **charger's `usbin_v` channel** | no battery at all |
| `QCOM_SPMI_ADC5` | pm8998 `adc@3100` (`qcom,spmi-adc-rev2`) | thermals/ADC missing |
| `QCOM_SPMI_ADC_TM5` | pm8998 `adc-tm@3400` (`qcom,spmi-adc-tm-hc`) | thermal monitor missing |
| `BATTERY_PMI8998_FG` | fuel gauge | no battery |
| `CHARGER_QCOM_SMB2` | charger (note: **SMB2**, not "SMBX") | no charger |

**Not needed** — joan does not instantiate them; the only
`qcom,spmi-vadc` reference in `pm8998.dtsi` is a `#include` of the
channel-constants header, not a device node:

    CONFIG_QCOM_SPMI_VADC    not needed
    CONFIG_QCOM_SPMI_IADC    not needed

Wi-Fi and Bluetooth can stay modules (`ATH10K_SNOC`, `BT_HCIUART`)
because nothing needs them during boot — but you must
`modules_install` for the running kernel's release string.

### The battery failure is worth spelling out

`qcom-smbx-charger: Couldn't get usbin_v IIO channel` followed by
`fuel-gauge: supplier charger@1000 not ready` means **RRADC**, not
ADC5. The channel comes from PMI8998's round-robin ADC
(`qcom,pmi8998-rradc`, `adc@4500`), a different driver from the PM8998
ADC. Enabling ADC5 alone changes nothing. Check
`/sys/kernel/debug/devices_deferred` — it names the culprit exactly.

## 4. The boot-chain size cliff

joan's bootloader hard-caps the **uncompressed** kernel at ~55.5 MB;
past that it hangs at the LG logo with no output (Aurel measured 55 MB
boots, 56+ hangs).

If you are close to it, the first thing to check is **`CONFIG_DEBUG_INFO_BTF`**.
Its `.BTF` section is 8.4 MB and — unlike the `.debug_*` sections —
it does land in `Image`. Turning it off (with `DEBUG_INFO_BTF_MODULES`)
took a fully-integrated joan kernel from 55.31 MB to 47.19 MB. Only
turn it back on if something actually needs BPF CO-RE.

Moving drivers to modules saves far less than you would expect — the
whole modem chain was worth 70 KB.

## 5. Current state (2026-08-08)

Working and device-verified:

- **Modem**: MBA authenticates, MPSS loads, `state: running`,
  `glink-edge.IPCRTR` up.
- **Battery**: 99%, 4.31 V, charger present, zero deferred probes.
- **Bluetooth**: `hci0` present, `crbtfw21.tlv` + `crnv21.bin`
  downloaded, "QCA setup on UART is completed". Note this contradicts
  earlier notes claiming `msm_serial` lacks serdev — it does not; the
  wall was missing firmware.
- **ICC/QoS**: 17/17 masters, 0 errors.

Not working:

- **IPA**: the node now exists (see below) and the driver gets to
  "IPA driver initialized", then fails:

      ipa 1e40000.ipa: Direct firmware load for ipa_fws.mdt failed with error -2
      ipa 1e40000.ipa: probe with driver ipa failed with error -2

  With `qcom,gsi-loader` absent the AP loads GSI firmware itself
  ("self" is the default), so `ipa_fws.mdt` and its `.b??` segments must
  be extracted like the modem's. The alternative is
  `qcom,gsi-loader = "modem"`, which hands the job to the modem and
  needs no extra firmware — worth trying first on joan, since the modem
  is up and healthy. Most sdm845 devices use "self";
  sc7180-trogdor-lte-sku uses "modem".

- **ModemManager**: reads the QRTR bus and enumerates every service, but
  reports "No modems were found". It needs IPA's rmnet/wwan netdevs to
  instantiate a modem object — pmaports !3531 says exactly this about
  OnePlus 5/5T ("blocking `ipa` from autoloading makes ModemManager not
  detect the modem over QRTR at all"). **There is no `ipa@` node in
  upstream `msm8998.dtsi`**; the driver supports `qcom,msm8998-ipa` but
  nothing instantiates it. Writing that node is the next concrete task,
  and it likely unblocks data, SMS and possibly Wi-Fi together.

- **Wi-Fi**: `ath10k_snoc` binds `18800000.wifi` and stops. No firmware
  request is ever made, so it is stalling before that — in the QMI
  handshake. `qrtr-lookup` shows the modem's services (registry,
  subsystem control, and remote file system once rmtfs runs) but
  **never the wlfw service (ID 69)**, which is what ath10k waits for.
  `wlanmdsp.mbn` is not referenced anywhere in the mainline kernel, so
  the kernel does not load it — the modem does, and it is not doing so.
  That is the open question.
