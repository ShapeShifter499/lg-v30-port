# Report: USB permanent fix + joan USB-C hardware map (2026-09-11)

Investigation: Fulgor (ZCode:zai-coding-plan/GLM-5.3), inline after two
subagent attempts died to network/captcha walls. STANDING APPROVAL (Lance):
always look at the code and reverse engineer stock ROM/kernel wherever it
helps the port.

## 1. Permanent gadget fix — found in the fork, one dependency line

`usb-signaller` ships in **`main/postmarketos-usb-moded`**, and that package
already carries the answer: two default-profile subpackages:

- `postmarketos-usb-moded-default-profile-charging` — default_mode="charging_only" (provider_priority 90) — what joan images currently get
- `postmarketos-usb-moded-default-profile-developer` — developer mode, "always enables usb networking" (provider_priority 100)

**Fix shipped**: `device-lge-joan` now depends on
`postmarketos-usb-moded-default-profile-developer` (committed, pkgrel 14).
The ~56 s teardown becomes a *reconfigure-with-network* instead of
teardown-to-charging. No mask unit, no own configfs script needed. Bonus:
usb-moded ships **umtprd** (a USB MTP responder with a systemd generator),
so MTP rides the same mode switch.

Context: the pmOS-native early-gadget path also exists —
`main/postmarketos-duranium/rootfs-usr-libexec-duranium-usb-gadget-setup`
(configfs NCM with RNDIS fallback, Linux Foundation VID 0x1d6b/PID 0x0104,
172.16.42.1, writes /run/usb-gadget-iface; called by
initramfs-usb-gadget.service). The signaller handoff at ~56-63 s is the
rootfs takeover of that initramfs gadget; with developer-default the
handoff keeps networking alive. (Possible residual blip during handoff —
verify on bench; sshd at +81 s per bench memory covers it.)

## 2. joan USB-C hardware map (stock RE)

- **PD/Type-C block**: PMI8998 USB block — dtb0.dts:1693 interrupts include
  `usbin-plugin`, `type-c-change` (plus usbin-uv/ov/icl); PD messaging PHY
  at dtb0.dts:1737 (`sig-tx/rx`, `msg-tx/...` interrupt names,
  `qcom,default-sink-caps` 5/9/12 V) — the charger/PD side.
- **DP↔USB-C integration**: `qcom,dp-usbpd-detection` node (dtb0.dts:16516)
  — downstream wires DP hotplug detect through the usbpd block.
- **SBU/DP mux is GPIO-controlled** (LG's own, not a PMIC mux):
  `lge,sbu-sel-gpio = tlmm 11`, `lge,gpio-sbu-oe = tlmm 16`,
  `lge,uart-sbu-sel-gpio = tlmm 90` (dtb0.dts:1207-1209, 1739-1740). This is
  the per-revision "USB-C SBU select" delta from the ten-DTB comparison —
  mainline-friendly (gpios + a mux selection at DP enable time).
- **VBUS source for host mode**: PMI8998 BOB (boost-or-buck) — the same
  rail the camera wiring uses (`bob_vreg-supply`).

## 3. Gap list

| Feature | State | What it needs |
|---|---|---|
| Gadget (NCM/serial) | **exists** | developer-default profile (shipped today) |
| MTP | **exists** | umtprd via usb-moded (same switch); needs web check for pmOS-recommended alternatives |
| Host mode (USB stick) | needs-DT (+verify) | dwc3-qcom role switching exists upstream; joan dts usb node is usb2-only with a role-switch comment (~:611-623); needs `usb-role-switch`, BOB VBUS regulator wiring as vbus-supply, and a PMIC typec/role source — the PMI8998 usb block has NO mainline driver, so expect a manual role-switch override experiment first |
| DP alt-mode video | needs-driver (hardest) | mainline `dp_display.c` compatibles are sc7180/sdm845/sm8350 — no msm8998; downstream uses the older `drm/msm/edp`+`mdss_dp` family for 8998 (dp pll + phy port); plus no mainline PMI8998 typec/PD driver for alt-mode negotiation, and the GPIO SBU mux needs wiring. Order: DP controller+PHY port first (display-side), alt-mode negotiation last |

## 4. Bring-up plan (smallest first)

1. **Host reads a USB stick**: wire BOB vbus-supply + usb-role-switch on the
   dwc3 node (DT), force role to host, test with a FAT stick. Bench item.
2. **DP controller bring-up** (no alt-mode): add msm8998 to mainline
   dp_display (or port the edp-family path), port the DP PLL/PHY, drive DP
   on a breakout/adapter with a fixed sink. Biggest single display task.
3. **Alt-mode**: needs a PMI8998 typec/PD driver (new) or TCPM glue + the
   SBU mux GPIOs; last.

Flagged needs-web-check: pmOS's current recommended MTP stack; whether any
mainline effort has started msm8998 DP (none found as of the 09-11 sweep).
