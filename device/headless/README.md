# Opt-in headless telephony and SMS for US998

This contribution publishes the source used for a separate LG V30 US998
postmarketOS bring-up on China Unicom. It does not select a desktop, enable
services, alter Bluetooth, dial, answer or send a message when checked out.
The source manifest identifies the published files without distributing a phone
image, firmware, libraries, subscriber state or private captures.

## Persistent TTY SMS

`sms/` is independent of imsd and uses ModemManager's system D-Bus API through
PyGObject/Gio. Python 3, SQLite, PyGObject with Gio/GLib typelibs, D-Bus,
ModemManager, and OpenRC are required. It works without a graphical session.

- The receiver only archives complete received messages (State=3), follows
  Messaging.Messages at startup even when SMS objects are absent from
  ObjectManager, and reconciles outgoing state. It never sends or replies.
- The SQLite parent is mode 0700 and the database is 0600. Raw message bodies
  and remote D-Bus error details are not written to the service log.
- Identical live incoming messages remain separate. A startup snapshot uses
  multiplicities to avoid duplicates after a receiver or bus-owner restart.
- Send intent is committed before Create/Send. Reusing a request ID cannot
  repeat a submission or change its recipient/body. A crash or ambiguous
  reply leaves a durable pending/unknown row; there is no automatic retry.
- `submitted` means ModemManager reports network submission. It is not proof
  of receipt or a read receipt. The outgoing list does not show a read badge.
- GSM7/UCS2 text is supported up to ten segments. Emoji/non-BMP text is
  rejected. The current CLI treats an unprefixed eleven-digit Chinese mobile
  number as +86; other destinations should use their full international form.
  Short numbers and service codes are rejected.

Stage the files into a package/rootfs (this does not enable the service):

```sh
sh device/headless/sms/install.sh /path/to/staging-root
```

On a deliberately configured device, the operator can enable `v30-sms` with
OpenRC. Its dependency is D-Bus, with soft ordering after NetworkManager; it
waits for ModemManager through bounded reconnects. That ordering is the only
runtime adaptation from the tested local service, which depended on the local
`v30-cellular` service. It has been syntax-checked, not device-tested here.

TTY commands, run explicitly as root:

```sh
v30-sms status
v30-sms list --unread
v30-sms read 1
v30-sms send FULL_INTERNATIONAL_NUMBER --file message.txt --request-id UNIQUE_ID
```

The service does not delete modem messages or implement retention, encryption
at rest, delivery guarantees, multi-SIM selection or a GUI. Disk-full recovery,
long-term modem storage management and real multipart SMS remain open gates.

## Voice and boot integration reference

`voice-reference/` preserves the tested OpenRC supervisor and per-call audio
source as a bring-up reference. It is deliberately not installed by the SMS
installer. Its exact release gate is `7.2.0-rc2-v30-r30`, based on the older
kernel commit `1b42626b2b448d8fe97d7e2e0a63dec93c3bdaae` plus local changes;
it must be ported and requalified before use on today's upstream kernel.

The reference uses `/opt/v30-mobile/{bin,lib,libexec}`, a `v30` audio user with
UID 10000, the LGV30 ALSA card, ADC3/TX8 capture, explicit speaker endpoints,
and private root-owned runtime/state directories. The supervisor owns its
children, IMS bearer bookkeeping, exact-interface firewall rules and persisted
operator backoff. It starts no call on its own. Each call validates parent
executable/boot/start-time identity, obtains an exclusive audio lock, starts a
private PipeWire graph, and restores mixers and closes PCM devices on teardown
or failure. The process executable is checked through /proc/PID/exe, avoiding
the transient empty-cmdline race that caused the earlier immediate hangup.

`ims-pdn-up.sh`, D-Bus policy and polkit policy are derived from Catcrafts
imsd at `2b5de7a60b3d9ecedab5fa34da40b2d3c8b26cab` and retain GPL-3.0-only
headers. Local PDN changes record owned bearers, cap MTU, assign the raw-IP
IPv6 address without Ethernet DAD, and leave firewall ownership to the
supervisor. The supplied policy still requires explicit call-control requests.

Porting prerequisites are intentionally visible rather than silently removed:

- `v30-audio` and `v30-unicom` are external board/carrier bring-up services;
  `v30-ipa` depends on them. IPA qmi_hold/boot_hold parameters and lowmem=1
  belong to the older local stack, not the current upstream configuration.
- `audio_session.py` checks the old q6core/WCD934x debug ABI before changing
  hardware. An absent parameter stops it; do not bypass the checks to claim
  compatibility. MIC BIAS3/MCLK routing is now already upstream.
- Build/install imsd, imsd-media and imsd-pcscf from source with the proposed
  interop patches. No binary or bundled library is included. The legacy
  one-shot entry point in media_helpers.py is retained as source context;
  the persistent call wrapper uses only forward_media().
- A carrier-specific NetworkManager data connection and modem/rmtfs firmware
  setup are outside this bundle. Do not copy subscriber settings between
  devices. The supervisor's IMS APN/profile settings are specific to the
  tested China Unicom setup.

The contributor's active profile remains pure landscape TTY (fbcon rotate=1)
with Bluetooth off. These are opt-in local policy, not replacements for the
upstream project's GUI or functioning Bluetooth support. No installer here
changes the boot partition, recovery, display manager or Bluetooth state.

## Host verification

```sh
python3 -m unittest discover -s device/headless/sms -p test_sms.py -v
python3 -m unittest discover -s device/headless/voice-reference -p test_integration.py -v
# Linux, root; synthetic ModemManager on a private bus AND network namespace:
unshare --net -- dbus-run-session -- sh -c \
  'export DBUS_SYSTEM_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"; exec python3 "$1"' \
  qa device/headless/sms/bench_private_bus.py
```

The private-bus test asserts that the real system bus and initial network
namespace are not used. It sends only to a fake service, verifies literal
Unicode/quotes, partial-to-complete reception, persistence over receiver
restart and one Create/Send despite request-ID reuse. The QA-directory change
uses a unique temporary directory so repeated host tests do not collide.
See the linked closure record for device evidence and its limits.

Assisted-by: Codex:OpenAI/GPT-6
Date: 2026-10-31
