# Aurel session 2026-08-23: regression reverted; APR reload bug root-caused and FIXED

Picks up from `HANDOFF-2026-08-23-next-session.md` (Ember). Lance approved both
the revert of the code-review session's uncommitted change and continuing the
VoLTE work. RAM-only boots only, per instruction.

---

## 1. The naming-conflict regression: REVERTED, independently re-derived

The working-tree change (`"11C05000"` -> `"VoiceMMode1"`, plus dropping
`char name[SESSION_NAME_LEN]` from the CVP v2 struct) was reverted with
`git checkout`. Before reverting I verified Ember's claims against primary
sources rather than taking the handoff on faith:

* Vendor `q6voice.c` lines 885/1009 copy **`VOICEMMODE1_VSID_STR`
  ("11C05000")** into the MVM/CVS APR payloads - that is the wire format.
* `"VoiceMMode1"` appears at vendor `msm-pcm-voice-v2.c` as a PCM id and in a
  userspace-name->id `strcmp`; it is **never copied into any payload**.
* Vendor struct `vss_ivocproc_cmd_create_full_control_session_v2_t` ends with
  `char name[SESSION_NAME_LEN]` (marked optional by the ADSP docs comment).
  The vendor header sits at `android_kernel_lge_msm8998/sound/soc/msm/qdsp6v2/q6voice.h:1212`.
* The live working-tree diff was byte-identical to the preserved patch
  (`docs/evidence/other-session-q6voice-rename.patch`) before revert -
  damage confirmed contained to that one file.

Tree restored to `02aad3751629c897bb186ac9e404b06d7e45e185`, byte-equal to
what passed four hardware cycles.

## 2. Module-reload bug: ROOT CAUSE FOUND AND FIXED

Ember recorded (writeup line ~1490): after rmmod/modprobe all three services
rebind (`bound` mask 7), commands go out, ADSP never answers, persists until
reboot. Suspect was q6voice's missing `.remove`.

### The actual mechanism is in the APR bus (`drivers/soc/qcom/apr.c`)

Replies are routed by `apr_do_rx_callback()` through
`idr_find(&apr->svcs_idr, hdr->dest_svc)`, requiring a bound driver. But:

* the idr entry was inserted ONCE, at device creation (`apr_add_device`);
* it was REMOVED at every driver unbind (`apr_device_remove`);
* nothing ever re-inserted it on re-probe.

So after one rmmod/modprobe cycle every reply hit a dead idr lookup and was
dropped ("APR: service is not registered"), while TX still worked (plain
rpmsg send). That reproduces every observed symptom. Note this asymmetry is
inherited verbatim from torvalds/master - a latent upstream bug, not local.

### Fixes (branch `joan/q6voice-mvm-probe`, now pushed)

* `4356e87c1` **soc: qcom: apr: register services for rx routing at bind time**
  - idr insert moved into bus probe (with unwind via driver `.remove` on
    failure); remove stays at unbind. Rx-routing lifetime == binding lifetime.
* `5f6732fb6` **ASoC: qdsp6: q6voice: add remove callbacks**
  - clears `svc->adev` before the device goes away, resets state,
    `mutex_destroy`. Completes bind/unbind symmetry client-side.

Both committed with Signed-off-by + Assisted-by trailers per repo hook.
PR #9 updated: now 4 files / 663 lines, base `joan/latest-clean-test`.

## 3. Hardware verification (RAM-only boots, image `boot-joan-voice-fix.img`)

Kernel `7.2.0-rc2-g5f6732fb6cb8`, modules staged to `/lib/modules/<ver>` on
the persistent rootfs, then coldplug-loaded:

* Sound card UP on coldplugged boot: `0 [LGV30]: sdm845 - LG-V30`.
* Four start/stop cycles PASS, distinct MVM handles 0x20/0x66/0xad/0xf4
  (matches Ember's original run exactly - same tree, same behaviour).
* **RELOAD TEST PASSED**: rmmod -> modprobe -> bound mask 7 ->
  full session built post-reload (all 7 steps status 0) -> clean teardown,
  twice (second run mvm=0x139/0x17b/0x66 across boots). Wire log captured
  showing `rsp op ... status 0x00000000` after reload.
* New dmesg lines confirm `.remove` fires: "q6voice: service unbound" x3.

Result lines: `RESULT: PASS=14 FAIL=0` (manual-load boot),
`RESULT: PASS=8 FAIL=0` (coldplug boot).

Open question closed: module reload no longer needs a reboot between loads.

## 4. Rig lessons added today (cost real time - do not repeat)

* **pmOS USB gadget = CDC-NCM (18d1:d001, serial "postmarketOS").** If nest
  lacks `cdc_ncm` loaded when the phone enumerates, NO netdev appears and the
  healthy phone looks dead. Fix: `sudo modprobe cdc_ncm cdc_ether`, then
  re-trigger (usbunbind/bind or replug), then add 172.16.42.2/24. The
  serial string is NOT an initramfs-rescue indicator; check
  `[pmOS-rd]: Switching root` in dmesg to see whether boot completed.
* **Never run two deploy/boot scripts concurrently against the phone.**
  Racing fastboot sessions produced `< waiting for any device >` hangs and
  stale processes holding the USB handle; `sudo pkill -f 'fastboot boot'`
  clears them. One script, one owner, poll its log.
* **`sysrq-b` lands in the FLASHED OS** (adbd visible, no pmOS USB-net).
  From there the path back is `adb reboot bootloader` -> `fastboot boot`,
  not another sysrq-b. adb is only visible in the flashed OS; pmOS netboot
  shows NO adbd - plan the entry path accordingly.
* **Foreground ssh commands time out mid-cycle** - launch detached with
  setsid and poll the log file (already in Ember's notes; reaffirmed hard).
* In-source-tree builds leave artifacts that block `O=` builds ("source tree
  is not clean"); mrproper needed Lance's config backed up first
  (`/data/buildcache/kbuild/joan-config-pre-sweep-20260823.config`,
  sha256 dba5fd22...). Build dirs now live under `/data/buildcache/kbuild/`.

## 5. Deploy/test tooling left in place (nest unless noted)

* `/tmp/verify-only.sh` - verify card + session + reload on a running kernel
* `/tmp/stage-and-load.sh` - stage modules + load stack without re-booting
* skyforge: `/data/buildcache/kbuild/{deploy-voice-fix,stage-and-load,voice-final-test,final-boot-test2,verify-only}.sh`
* build dir `/data/buildcache/kbuild/build-voice-fix` (O= build, clean);
  module staging tree `/data/buildcache/kbuild/modstage-voice-fix`

## 6. Where things stand for VoLTE

Done and hardware-proven: cellular data (WRR fix), voice session bring-up +
teardown, sound card, earpiece route powering up, **module reload**.

Remaining, in order:
1. **Listen to the earpiece** (needs human ears; route powers up end-to-end).
   Mixer route is in HANDOFF-2026-08-22 section AUDIO / handset path.
2. Real audio through the voice session: start SLIMBUS_0_RX/TX AFE ports;
   a PCM front-end belongs here instead of debugfs (handoff item #4/#5).
3. IMS/SIP userspace stack; groundwork in
   `~/.ember/workspace/joan-cellular-2026-08-23/` (imsprobe/imsscan/lgims;
   services 701-707 answer, 704 silent - worth following up).
