# LG V30 reset-cause handoff — PS_HOLD secure-side reset

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

## Current headline

The LG V30 (`joan`) mainline reset is still a controlled PS_HOLD reset. The
secure/liveness hypothesis remains active, but Aurel has now rejected several
specific first-second deltas: downstream's DLOAD-off SCM argument shape,
downstream-style QSEE log-buffer registration, RPM `rpm_requests` rpmsg
reachability as a standalone liveness oracle, a minimal downstream PMI8998
BOB-mode RPM vote, a DT-backed PM8998 L19 3.3 V always-on default vote,
a broader DT-backed PM/RPM L18+L19+BOB overlay vote bundle, and a TCSR
DLOAD/restart-cookie phandle matching downstream's `tcsr-boot-misc-detect`
address, PM8998 PON S3/reset-sequence parity, optional Kryo SCM errata, and the
obvious downstream `watchdog_v2`/QSEECOM probe paths checked in K025.

## Evidence preserved from the PON / reset-cause pass

Baseline controlled bootloader chain and post-mainline-crash chain both report
SID0 power-off reason `PS_HOLD`:

```text
PMIC@SID0 Power-on reason: Triggered from Hard Reset and 'cold' boot
PMIC@SID0: Power-off reason: Triggered from PS_HOLD
PM: 0: PON=0x21:PON1:HARD_RESET: POFF=0x2:PS_HOLD: FAULT1=0x40:UVLO
lge.bootreason=NORMAL / bootreasoncode=0x20
```

Interpretation: the reset is hardware-indistinguishable from a deliberate secure
reset. It is not currently explained by PMIC watchdog, thermal bite, keypad/GP
fault, ordinary Linux panic, APSS watchdog node/petting, CPU-idle, secondary CPU
bringup, high-memory secure/shared pool allocation, DLOAD-off argument shape, a
standalone QSEE log-buffer registration ping, RPM `rpm_requests` rpmsg
reachability alone, a bare PMI8998 BOB-mode RPM vote, or a single DT-backed
PM8998 L19 3.3 V always-on default vote, a broader standard DT-backed
PM/RPM L18+L19+BOB overlay vote bundle, the downstream-observed TCSR
DLOAD/restart-cookie route, PM8998 PON S3/reset-sequence parity, optional Kryo
SCM errata, or the obvious downstream `watchdog_v2`/QSEECOM probe paths checked
in K025.

## Concrete rejected paths so far

- `SEC_WDOG_DIS` via downstream/mainline/raw SMC variants: rejected. Downstream's
  own runtime sysfs path also failed with `0x42000107 ret=-2`.
- `panic=30`: rejected.
- APSS watchdog DT disable / downstream-style pet / EN=3: rejected.
- Single-core boot (`maxcpus=1`): rejected.
- CPU idle disabled (`cpuidle.off=1 nohlt`): rejected.
- Downstream high-memory secure/shared pool no-map reservation: rejected.
- IMEM oracle showed the useful readback route was PON/PS_HOLD, not LGE
  restart-reason decode.
- Downstream DLOAD-off SCM argument shape `(0, 0)`: rejected.
- Downstream-style QSEE log-buffer registration `SCM_QSEEOS_FNID(1, 6)`: rejected.
- RPM `rpm_requests` rpmsg reachability/timing oracle: no survival.
- RPM BOB-mode state-changing oracle (`BOBB:1` `bobm=2` active/sleep): no
  diagnostic channel; reset still ended as SID0 `PS_HOLD`.
- DT-backed PM8998 L19 default-vote oracle (3.3 V, boot-on, always-on): no
  diagnostic channel; reset still ended as SID0 `PS_HOLD`.
- Broader DT-backed PM/RPM overlay oracle (L18 boot-on, L19 3.3 V
  boot/always-on, BOB 3.312 V boot/always-on): no diagnostic channel; reset
  still ended as SID0 `PS_HOLD`.
- TCSR DLOAD/restart-cookie oracle (`qcom,dload-mode = <&tcsr_regs_2 0x13000>`):
  no diagnostic channel; reset still ended as SID0 `PS_HOLD`.

- K025 secure-interface archaeology: downstream `watchdog_v2`/QSEECOM obvious early paths produced no valid boot oracle; no image built.

## New Aurel test: DLOAD-off SCM argument-shape oracle

Downstream reference:

- `android_kernel_lge_msm8998/drivers/power/reset/msm-poweroff.c`
- LGE builds default `download_mode = 0`.
- `pure_initcall(msm_restart_init)` calls `set_dload_mode(download_mode)`.
- For ARMv8 this calls SCM boot command `SCM_DLOAD_CMD` (`0x10`) with args
  `(0, 0)` for the off request.

Mainline delta:

- `linux-mainline-v30/drivers/firmware/qcom/qcom_scm.c`
- Mainline already calls SCM boot command `QCOM_SCM_BOOT_SET_DLOAD_MODE` (`0x10`),
  but for off it encoded args as `(0x10, 0)`.

Oracle:

- Patch:
  `out/aurel-latest-dload-off-argshape-test-2026-07-06.patch`
- Patch sha256:
  `eb285f2d73b2711fa505c0938183954b18ebb125735ae69176e7311fc8f1a5a0`
- Image:
  `out/boot-joan-latest-dload-off-argshape.img`
- Image sha256:
  `423d0c7f306a0d1617ade6577c8cb012df71cda6d6f8a08ab731dc4e79a26457`
- Size:
  `15736832` bytes

Result:

- RAM-only one-client `fastboot boot`.
- No flashing; no phone-storage writes; no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.516s`.
- No mainline USB/mass-storage/diag channel appeared.
- LineageOS adb returned at `t+44.3s`.
- Post-reset dmesg again showed SID0 `PS_HOLD`.

Conclusion: `SET_DLOAD_MODE` argument shape is not the missing liveness handshake.


## New Aurel test: QSEE/QSEEOS log-buffer oracle

Downstream reference:

- `android_kernel_lge_msm8998/drivers/firmware/qcom/tz_log.c`
- `tzdbg_register_qsee_log_buf()` allocates a 32 KiB QSEE log buffer and calls
  `SCM_QSEEOS_FNID(1, 6)` with args `(pa, len)` / arginfo `0x22`.
- Mainline already performs the downstream TZ feature/version query in
  `qcom_scm_qseecom_init()`, so the oracle tested only the missing log-buffer
  registration ping.

Oracle:

- Patch:
  `out/aurel-latest-qsee-logbuf-oracle-2026-07-06.patch`
- Patch sha256:
  `68b0883cae085712a446475c5ae3bd723defb056ddd28e6babfe18521ce797d3`
- Image:
  `out/boot-joan-latest-qsee-logbuf.img`
- Image sha256:
  `6a99c6f2c653e21d2cbba2df7ad2d392dbbcc40f0db7fef63efd599d57b7eb93`
- Size:
  `15736832` bytes

Result:

- RAM-only one-client `fastboot boot`.
- No flashing; no phone-storage writes; no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.513s`.
- No mainline USB/mass-storage/diag channel appeared.
- LineageOS adb returned at `t+52.2s`.
- Post-reset dmesg again showed SID0 `PS_HOLD`.

Conclusion: standalone QSEE log-buffer registration is not the missing liveness
handshake.


## New Aurel test: RPM `rpm_requests` reachability oracle

Downstream reference:

- `android_kernel_lge_msm8998/drivers/soc/qcom/rpm-smd.c`
- Downstream dmesg shows `msm_rpm_dev_probe: APSS-RPM communication over GLINK`
  around `0.317s` and `rpm_requests` link configuration around `0.332s`.
- Mainline has `qcom,glink-rpm` / `qcom,glink-smd-rpm` in `msm8998.dtsi`, and
  `CONFIG_RPMSG_QCOM_GLINK_RPM`, `CONFIG_QCOM_SMD_RPM`, `CONFIG_QCOM_SMEM`, and
  `CONFIG_QCOM_SMP2P` are built in.

Oracle:

- Patch:
  `out/aurel-latest-rpm-rpmsg-reachability-oracle-2026-07-06.patch`
- Patch sha256:
  `a92efaa88f7717d5762fa71bd2d22c84510bf13c4b43a3e22f893bd25bc895f1`
- Image:
  `out/boot-joan-latest-rpm-rpmsg-oracle.img`
- Image sha256:
  `d7b039b381ad83c61a4e7bfdf3005fa143a8fc5701c90dbf9faf06edfe1bed6b`
- Size:
  `15740928` bytes
- Fastboot transcript:
  `out/aurel-rpm-rpmsg-fastboot-2026-07-06.txt`
- PON evidence:
  `out/aurel-rpm-rpmsg-pon-2026-07-06.txt`

Result:

- RAM-only one-client `fastboot boot`.
- No flashing; no phone-storage writes; no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.518s`.
- No mainline USB/mass-storage/diag channel appeared.
- LineageOS adb returned at `t+58.3s`.
- Post-reset dmesg again showed SID0 `PS_HOLD`.

Conclusion: RPM `rpm_requests` rpmsg reachability alone is not enough to satisfy
or prevent the secure-side liveness/reset policy. The delayed host return suggests
mainline likely reaches the RPM rpmsg probe before reset, so a total absence of
RPM-channel setup is weaker as a root cause; still compare actual downstream RPM
resource votes and SMEM/boot-state cookies separately.


## New Aurel test: RPM BOB-mode state-changing oracle

Downstream reference:

- `android_kernel_lge_msm8998/arch/arm64/boot/dts/qcom/msm8998-regulator.dtsi`
- `android_kernel_lge_msm8998/arch/arm64/boot/dts/lge/msm8998-joan/msm8998-joan-common/msm8998-joan-common-pm.dtsi`
- Downstream enables `rpm-regulator-bobb` and sets `qcom,init-bob-mode = <2>`
  (`AUTO`) for `pmi8998_bob` plus pin-control BOB children.
- Mainline joan has `rpm_requests`, but no `rpm-pmi8998-regulators` / BOB child
  nodes, so it never sends this downstream default vote as a regulator action.

Oracle:

- Patch:
  `out/aurel-latest-rpm-bob-mode-oracle-2026-07-06.patch`
- Patch sha256:
  `eca4d41b1532903e541118e951f9dda4e366fed3b89a2feedd08915386cbd7df`
- Image:
  `out/boot-joan-latest-rpm-bob-mode.img`
- Image sha256:
  `e7ccb54378f39b84a3497590844d26d504e5cc770040190bab86e5e845f7c1c9`
- Size:
  `15736832` bytes
- Fastboot transcript:
  `out/aurel-rpm-bob-mode-fastboot-2026-07-06.txt`
- PON evidence:
  `out/aurel-rpm-bob-mode-pon-2026-07-06.txt`

Result:

- RAM-only one-client `fastboot boot`.
- No flashing; no phone-storage writes; no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.515s`.
- No mainline USB/mass-storage/diag channel appeared.
- The host monitor timed out at `t+108.4s` with no adb and no mainline USB
  channel; a follow-up host check then found LineageOS adb visible.
- Post-reset dmesg again showed SID0 `PS_HOLD`.

Conclusion: a bare downstream-style BOB-mode vote is not sufficient to expose
mainline diagnostics or prevent the PS_HOLD reset. Its much longer timing keeps
full downstream RPM regulator/default-vote parity worth comparing next, but this
single vote is not the fix by itself.

## New Aurel test: DT-backed RPM L19 default-vote oracle

Downstream reference:

- `android_kernel_lge_msm8998/arch/arm64/boot/dts/lge/msm8998-joan/msm8998-joan-common/msm8998-joan-common-sound.dtsi`
- Downstream joan forces `pm8998_l19` to 3.3 V with `qcom,init-voltage`,
  `qcom,vdd-voltage-level`, and `regulator-always-on`.
- Mainline joan inherited the generic MSM8998 `l19` 3.008 V default with no
  `regulator-boot-on` / `regulator-always-on` flags.

Oracle:

- Patch:
  `out/aurel-latest-rpm-l19-always-on-oracle-2026-07-06.patch`
- Patch sha256:
  `41bb06f48df489e454c4d44aab7284e6990ac97367b8b8925e68cc642c95df45`
- Image:
  `out/boot-joan-latest-rpm-l19-always-on.img`
- Image sha256:
  `84134c0d71c7f7eafae9e6a268c50302238a002b6c11c229baa6b52a6ee96e04`
- Size:
  `15736832` bytes
- Fastboot transcript:
  `out/aurel-rpm-l19-always-on-fastboot-2026-07-06.txt`
- PON evidence:
  `out/aurel-rpm-l19-always-on-pon-2026-07-06.txt`

Result:

- RAM-only one-client `fastboot boot`.
- No flashing; no phone-storage writes; no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.517s`.
- No mainline USB/mass-storage/diag channel appeared.
- LineageOS adb returned at `t+57.8s`.
- Post-reset dmesg again showed SID0 `PS_HOLD`.

Conclusion: a single DT-backed downstream L19 default vote is not sufficient to
prevent the controlled PS_HOLD reset or expose diagnostics. It strengthens the
case for broader PM/RPM regulator parity, but not another L19-only retry.


## New Aurel test: DT-backed PM/RPM overlay parity oracle

Downstream reference:

- `android_kernel_lge_msm8998/arch/arm64/boot/dts/lge/msm8998-joan/msm8998-joan-common/msm8998-joan-common-pm.dtsi`
- `android_kernel_lge_msm8998/arch/arm64/boot/dts/lge/msm8998-joan/msm8998-joan-common/msm8998-joan-common-sound.dtsi`
- Downstream common PM/sound overlays set L18 2.704 V defaults, L19 3.3 V
  always-on, and PMI8998 BOB mode/pin-control defaults.
- Mainline cannot express downstream BOB mode/pin-control KVPs through its simple
  SMD regulator DT binding, so this oracle tested the standard mainline-capable
  voltage/enable subset: L18 boot vote, L19 fixed 3.3 V boot/always-on, and BOB
  fixed 3.312 V boot/always-on.

Oracle:

- Patch:
  `out/aurel-latest-rpm-pm-overlay-oracle-2026-07-06.patch`
- Patch sha256:
  `8b6d4480fe54b7ae7300ecb80b8b4091b542adadb57d1dc986851ec72dfb3c3f`
- Image:
  `out/boot-joan-latest-rpm-pm-overlay.img`
- Image sha256:
  `de729e6eff09e997de15bdfb0fcf29890e86765228d691f5bb1ca1e185806365`
- Size:
  `15736832` bytes
- Fastboot transcript:
  `out/aurel-rpm-pm-overlay-fastboot-2026-07-06.txt`
- PON evidence:
  `out/aurel-rpm-pm-overlay-pon-2026-07-06.txt`

Result:

- RAM-only one-client `fastboot boot`.
- No flashing; no phone-storage writes; no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.518s`.
- No mainline USB/mass-storage/diag channel appeared.
- LineageOS adb returned at `t+30.6s` after fastboot.
- Post-reset dmesg again showed SID0 `PS_HOLD`.

Conclusion: broader standard DT-backed PM/RPM regulator voltage/enable parity is
not sufficient to prevent the controlled PS_HOLD reset or expose diagnostics.
The next test should not be another standard regulator voltage/enable bundle.


## New Aurel test: TCSR DLOAD/restart-cookie oracle

Downstream reference:

- `android_kernel_lge_msm8998/arch/arm64/boot/dts/qcom/msm8998.dtsi`
- Downstream defines `qcom,msm-imem@146bf000` with restart/dload/boot-stat
  children, plus a `qcom,pshold` `tcsr-boot-misc-detect` resource at physical
  `0x1fd3000`.
- `0x1fd3000` is `tcsr_regs_2 + 0x13000`; mainline MSM8998 had `tcsr_regs_2` but
  no SCM `qcom,dload-mode` phandle and no IMEM restart-reason node.

Oracle:

- Patch:
  `out/aurel-latest-tcsr-dload-cookie-oracle-2026-07-06.patch`
- Patch sha256:
  `bd4c3fc21b3d10260fe2b7c2ee96291966fdd9b7f43424c97288e876d1e86b97`
- Image:
  `out/boot-joan-latest-tcsr-dload-cookie.img`
- Image sha256:
  `0ba46735f6f6fac182f3de3f67fe46f5c60c26948be7b1193f7c7147b48645dd`
- Size:
  `15736832` bytes
- Fastboot transcript:
  `out/aurel-tcsr-dload-cookie-fastboot-2026-07-06.txt`
- PON evidence:
  `out/aurel-tcsr-dload-cookie-pon-2026-07-06.txt`

Result:

- RAM-only one-client `fastboot boot`.
- No flashing; no phone-storage writes; no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.513s`.
- No mainline USB/mass-storage/diag channel appeared.
- LineageOS adb returned at `t+55.5s` from test start.
- Post-reset dmesg again showed SID0 `PS_HOLD`.

Conclusion: routing DLOAD-mode clearing through the downstream-observed TCSR
boot-misc cookie is not the missing standalone liveness handshake.


## Aurel follow-up: PM8998 PON S3 source/debounce oracle rejected

After the TCSR DLOAD/restart-cookie oracle, Aurel compared downstream joan
PMIC/PON setup against mainline and isolated one unsupported downstream PON
delta:

- downstream PM8998 PON root properties:
  - `qcom,s3-debounce = <32>`
  - `qcom,s3-src = "kpdpwr-and-resin"`
- mainline `qcom-pon` does not consume these properties, so a pure DTS change
  would not test the delta.

Oracle:

- Patch:
  `out/aurel-latest-pon-s3-oracle-2026-07-06.patch`
- Patch sha256:
  `e8dfba3949f4ace1d678ed94ce7e254287197ba4c6ee0d6368d4efa642dc051d`
- Config artifact:
  `out/aurel-latest-pon-s3-oracle-config-2026-07-06.txt`
- Config artifact sha256:
  `bababe3d52ff1bd1e7b6ede056c8986696260024010f38ab56696039b0bb193c`
- Image:
  `out/boot-joan-latest-pon-s3-oracle.img`
- Image sha256:
  `2c83d4782aa60564c840efe5122ebfeb9aa30f8e0aea8bab10fc7d70f6fb2c31`
- Size:
  `15740928` bytes
- Fastboot transcript:
  `out/aurel-pon-s3-fastboot-2026-07-06.txt`
- Fastboot transcript sha256:
  `c8222c05a1ee402d091d708bc14b31c64b7d0b1da0b3aedd99f499a34c0a5f62`
- PON evidence:
  `out/aurel-pon-s3-pon-2026-07-06.txt`
- PON evidence sha256:
  `c5acb2a3c56a0a1f1e0c42d5b85c04ea95033f3690cee79251ede518ef048c4d`

Result:

- RAM-only one-client `fastboot boot`.
- No flashing; no phone-storage writes; no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.510s`.
- No mainline USB/mass-storage/diag channel appeared.
- LineageOS adb returned at `t+30.5s`.
- Post-reset dmesg again showed SID0 `PS_HOLD`.

Conclusion: downstream PM8998 PON S3 source/debounce parity is not the missing
standalone liveness handshake.


## PM8998 PON reset-sequence/S1/S2 oracle — rejected

Aurel tested the fuller downstream PM8998 PON reset-sequence delta after the S3
source/debounce-only oracle failed.

Patch and image:

- Patch:
  `out/aurel-latest-pon-reset-seq-oracle-2026-07-06.patch`
- Patch sha256:
  `588264cfb140c0c307a57b8898f5c1c77bf8fa623da32e68ffaa7ce66f9f552c`
- Config artifact:
  `out/aurel-latest-pon-reset-seq-oracle-config-2026-07-06.txt`
- Config artifact sha256:
  `bababe3d52ff1bd1e7b6ede056c8986696260024010f38ab56696039b0bb193c`
- Image:
  `out/boot-joan-latest-pon-reset-seq-oracle.img`
- Image sha256:
  `a0c0e2b6448981798d5cc5b03a4804504caaedff7705a896a42883d86786ee12`
- Size:
  `15740928` bytes
- Fastboot transcript:
  `out/aurel-pon-reset-seq-fastboot-2026-07-06.txt`
- Fastboot transcript sha256:
  `71f352f65822e597d37a769d374408bb06864c6e2739a839a4cda5132b3b7fd1`
- PON evidence:
  `out/aurel-pon-reset-seq-pon-2026-07-06.txt`
- PON evidence sha256:
  `c643c1db1c555052bdb1da483062e86d5b5b691d16d3df8a70e7c928e83d005d`
- Clean post-revert image:
  `out/boot-joan-latest-clean-post-pon-reset-seq-oracle.img`
- Clean post-revert image sha256:
  `d543f234ab848f2de12191eca3cf2df2aa87b04711e4665564da93f5cf57f418`

Result:

- RAM-only one-client `fastboot boot`.
- No flashing; no phone-storage writes; no `fastboot getvar`.
- Fastboot protocol succeeded:
  `Sending 'boot.img' ... OKAY`, `Booting ... OKAY`, total `5.522s`.
- No mainline USB/mass-storage/diag channel appeared.
- LineageOS adb returned at `t+57.6s` host-script time, about `46.3s` after the
  fastboot boot command returned.
- Post-reset dmesg again showed SID0 `PS_HOLD`.

Conclusion: fuller downstream PM8998 PON reset-sequence/S1/S2 parity is not the
missing standalone liveness handshake.


## CPU/Kryo SCM errata comparison — no boot oracle

Aurel compared downstream `drivers/soc/qcom/scm-errata.c` before creating another
RAM-boot image.

The downstream helper can issue SCM BOOT command `0x12` for Kryo errata toggles
(E74/E75 enable arg `0x1`, E76 disable arg `0x100`), but it is optional debugfs
infrastructure (`CONFIG_QCOM_SCM_ERRATA`, depending on `DEBUG_FS` and `QCOM_SCM`)
and was not enabled in the joan defconfigs checked. Its init path creates debugfs
files and registers a CPU hotplug notifier; it does not immediately apply the
calls to already-online boot CPUs.

Conclusion: CPU/Kryo SCM errata was rejected at comparison time as a standalone
oracle. It is not active downstream joan default boot-state parity, so no kernel
patch was built or booted for this path.

## Next best single oracle

Do not repeat DLOAD SCM argument-shape, TCSR DLOAD-cookie phandle, QSEE-log
registration, RPM reachability, bare BOB-mode, single L19 default-vote,
standard DT L18+L19+BOB voltage/enable bundle, PM8998 PON S3
source/debounce parity, PM8998 PON reset-sequence/S1/S2 parity tests, or the
optional downstream CPU/Kryo SCM errata debugfs helper as the next standalone
test. Mainline already performs the TZ feature/version
query, the QSEE log-buffer ping did not prevent PS_HOLD, the RPM rpmsg
reachability oracle only shifted timing without exposing diagnostics, and the
BOB-mode vote extended timing but still returned to LineageOS with SID0
`PS_HOLD`.

Next compare another first-second downstream secure-liveness/platform-state delta
against mainline, especially one of:

- full downstream RPM regulator/default-vote parity or another concrete RPM vote,
  not mere `rpm_requests` reachability, not just BOB `bobm=2`, not just
  L19 `3300000` + always-on/boot-on, and not just standard DT L18+L19+BOB
  voltage/enable votes;
- fuller IMEM/reboot-mode/normal restart-reason modeling, only if kept distinct
  from the rejected TCSR DLOAD-cookie phandle;
- LGE/Qualcomm restart/boot-state cookies not covered by the prior IMEM oracle;
- another concrete QSEE/QSECOM state transition only if downstream evidence shows
  it runs before the reset window and differs from mainline.

Keep the same rule: one oracle at a time, RAM-only `fastboot boot`, save patch
under `out/`, then revert/rebuild clean and update the ledger.

## Caveat for expectations

If the reset is a secure watchdog/liveness service that can only be serviced from
signed TZ/aboot firmware, it may be unfixable purely from mainline Linux. The
US998 is unlocked, so there may still be a path, but do not promise one.

## Current state after Aurel update

- Kernel branch `joan/latest-clean-test` clean and rebuilt.
- Harness docs updated through the PM8998 PON reset-sequence/S1/S2 oracle and the CPU/Kryo SCM errata comparison.
- Phone parked back in LineageOS; adbd returned to non-root after PON readback.
- No fastboot client left running.
- No packages installed.


## Aurel follow-up — secure-interface archaeology K025 cancelled before boot

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

Aurel followed Ember's session-2 handoff by inspecting downstream early
secure/TZ/SCM paths before spending another boot cycle. Goal: find exactly one
active downstream-default, early, state-changing secure call that mainline lacks
and that is safe enough to test as a debug oracle.

Sources compared:

- downstream `drivers/soc/qcom/watchdog_v2.c`
- downstream `drivers/misc/qseecom.c`
- downstream `drivers/soc/qcom/qsee_ipc_irq_bridge.c`
- downstream `include/soc/qcom/qseecomi.h`
- downstream MSM8998/joan DT and joan defconfigs
- mainline `drivers/firmware/qcom/qcom_scm.c`
- mainline `drivers/firmware/qcom/qcom_qseecom.c`
- mainline `drivers/firmware/qcom/Kconfig`
- mainline MSM8998/joan DT and active `.config`

Findings:

- `SEC_WDOG_DIS` is still the only obvious secure-watchdog disable path in
  downstream `watchdog_v2.c`. It was already rejected, and downstream LineageOS's
  own sysfs disable path fails on this device with `0x42000107 ret=-2`.
- The other secure call visible in `watchdog_v2.c`, `SCM_SVC_UTIL` /
  `SCM_SET_REGSAVE_CMD` (`cmd 0x2`), registers a CPU register-save page for
  watchdog-bite dump collection. Failure only means registers will not be dumped
  on a dog bite. It is crashdump setup, not a pet/ack/keepalive.
- Current mainline already has `CONFIG_QCOM_SCM=y`, `CONFIG_QCOM_TZMEM=y`, and
  `CONFIG_QCOM_QSEECOM=y`, and `qcom_scm_probe()` already calls
  `qcom_scm_qseecom_init()`. That function performs the QSEECOM version query
  before applying the machine allowlist, so repeating the version query is not a
  new oracle.
- Mainline skips creating the `qcom_qseecom` platform device on joan because
  `lge,joan` is not in the QSEECOM allowlist. Enabling it would currently mainly
  add a `qcom.tz.uefisecapp` app lookup, which is not downstream joan default
  liveness parity and should not be the next reset oracle.
- Downstream `qseecom_probe()` can send `QSEOS_APP_REGION_NOTIFICATION`, but the
  downstream MSM8998 qseecom node sets `qcom,appsbl-qseecom-support`; with that
  property true, downstream treats appsbl/boot firmware as already handling the
  region/commonlib state and skips the region notification path. Joan variant
  DTs only resize `qseecom_mem` to `0x1800000`; they do not remove the property.
- `qsee_ipc_irq_bridge.c` is char-device/IRQ/SSR notification plumbing and does
  not issue an SCM/QSEE liveness call at probe.
- `CONFIG_QCOM_EARLY_RANDOM=y` appears in joan defconfigs, but source search in
  this tree only found config references, not a concrete implementation to
  transplant or compare.

Decision:

- No K025 boot image was built.
- No K025 fastboot boot was run.
- This path is recorded as comparison-only / no-test so future agents do not
  waste a boot on inactive or already-covered calls.

Artifact:

- `out/aurel-secure-interface-archaeology-k025-2026-07-06.txt`
- sha256 `f1a47398089fd7640179a042a8f3016005c3526b5d498fad58cbed5f4f06b630`

Next better targets:

- downstream LGE panic/restart-reason plus IMEM/SMEM boot-cookie setup, kept
  distinct from the already-rejected TCSR DLOAD phandle oracle;
- any early `SCM_SVC_BOOT` or TZ setup before/around downstream `msm_watchdog`
  init that is not `SEC_WDOG_DIS` and not dump-only;
- stock-RAM-boot/downstream dmesg diffs around the first second, especially
  secure monitor, qseecom, msm_watchdog, and restart-reason lines.


## Aurel follow-up — K026 LGE IMEM default restart-reason oracle tested

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes:gpt-5.5
Date: 2026-07-06

Downstream joan enables `CONFIG_LGE_HANDLE_PANIC=y`; downstream `lge_handle_panic`
maps IMEM `0x146bf000` in an early initcall and writes `LGE_RB_MAGIC | LGE_ERR_TZ`
(`0x6d630300`) to restart_reason offset `0x65c`. Mainline has no equivalent LGE
panic/IMEM restart-reason setup. Aurel therefore reused Ember's debug-only
`joan/imem-oracle` commit `f0d368d28` and repackaged it with the safer K023
`panic=0` null-init classifier.

Artifacts:

- Patch: `out/aurel-lge-imem-default-reason-k026-2026-07-06.patch`
  sha256 `d68baabab6c1b82d0b976b826de49a5aed621747893bf5fe40fa98fba8a89f62`
- Image: `out/boot-joan-imem-k026.img`
  sha256 `ccf08dbea0e889fa11404335d423e46e5078f37883469234694aff4d3939d035`
- Result artifact: `out/aurel-lge-imem-k026-result-2026-07-06.txt`
- Logs: `out/aurel-imem-k026-fastboot-2026-07-06.txt`,
  `out/aurel-imem-k026-monitor-2026-07-06.txt`,
  `out/aurel-imem-k026-pon-2026-07-06.txt`

Device result:

- RAM-only `fastboot boot` completed normally (`Sending`/`Booting` OKAY, total
  `5.513s`).
- No mainline USB/survivor beacon appeared.
- LineageOS adb returned at `t+49.1s`; classification
  `lineageos_returned_reset_not_fixed`.
- Post-reset PON still showed SID0 `PS_HOLD`.
- Returned downstream kernel reported
  `androidboot.product.lge.bootreasoncode=0x6D630309` and
  `LGE BOOT REASON: 0x6d630309`.

Interpretation:

- K026 is rejected as a survival fix: the LGE IMEM default restart-reason write
  does not keep mainline alive.
- It is useful evidence: `0x6D630309` decodes as LGE magic + TZ class + an
  undocumented subreason `0x09` in this downstream kernel header. It is not the
  named TZ non-secure watchdog bark (`0x3a`) or thermal secure bite (`0x3b`).
- Do not repeat K026. Next useful work is to identify LG/XBL/TZ subreason `0x09`
  or the early secure-world handshake that produces it.
