#!/usr/bin/env python3
"""Triage porthole-dev's msm8998 7.2 patches for the LG V30 (joan) port.

Code decides what code can: whether each patch applies to our kernel tree,
is already in it, or conflicts. Jev (TypeSafe System One) supplies the
semantic judgments: is the patch about hardware/software the V30 port uses,
which subsystem, and does it fix a crash/hang/reset/corruption.
"""
import concurrent.futures as cf
import json, os, re, subprocess, sys, urllib.request

PATCHES = sys.argv[1]           # directory of NNNN-*.patch
TREE = sys.argv[2]              # kernel worktree to check against
OUT = sys.argv[3]               # output JSON

JOAN = {
    "device": "LG V30 (joan), mainline Linux 7.2 port for postmarketOS",
    "hardware": [
        "Qualcomm MSM8998 SoC: Kryo 280 CPUs with OSM + CPRh DVFS, SAW/SPM, LMh limits",
        "Adreno 540 GPU (a5xx, no GMU), VDD_GFX on PM8005 S1, GPMU/limits",
        "DPU display, LG SW43402 6.0in 1440x2880 DSC command-mode AMOLED over DSI",
        "ST FTS touchscreen (stmfts)",
        "WCD9340 codec over SLIMbus with the ADSP (q6afe/q6asm), TFA9872 speaker amp, ES9218P hi-fi DAC, MBHC headset jack",
        "WCN3990 Wi-Fi (ath10k_snoc) and Bluetooth (btqca over UART)",
        "PMI8998/PM8998/PM8005 PMICs, PMI8998 charger + fuel gauge, BQ25898S parallel charger",
        "UFS 2.1 storage, microSD (sdhci-msm), DWC3 USB-C with TCPM, QMP USB3/DP PHY",
        "CAMSS with CCI; Sony IMX351 rear camera; VL53L0X laser AF",
        "Modem (MSS remoteproc), IPA, RPM/RPMh-era interconnect (msm8998 bimc/cnoc)",
        "tsens thermal zones, cpufreq and GPU cooling",
    ],
    "not_on_this_phone": [
        "Pixel 2 (wahoo/taimen/walleye) specific panels other than SW43402, their touch controllers, Maxim/Samsung PMIC or charger parts, NFC/camera sensors other than IMX351/VL53L0X",
        "SDM845, SM8x50 and other SoCs",
    ],
}

QUESTIONS = {
    "relevant": {
        "type": "noul",
        "instructions": "Would this patch change the behaviour of hardware or kernel software that the LG V30 port described in `device` actually uses? Shared MSM8998 SoC code, the SW43402 panel and generic subsystems the V30 uses count. Changes that only touch another board's device tree or parts listed in `device.not_on_this_phone` do not count.",
        "criteria": {
            "true": "The patch affects code, firmware handling or device-tree nodes the LG V30 port exercises",
            "false": "The patch only affects other boards, other SoCs, or parts the LG V30 does not have",
        },
    },
    "subsystem": {
        "type": "choice",
        "instructions": "Which subsystem is this patch mainly about?",
        "criteria": {
            "cpu_dvfs": "CPU frequency/voltage scaling, OSM, CPR, SPM/SAW, LMh, cpuidle",
            "gpu": "Adreno GPU, GPU power, GPU firmware, devfreq for the GPU",
            "display": "DPU/DSI/DSC, panels, backlight, pageflip/vblank",
            "audio": "Codecs, SLIMbus, SoundWire, ASoC, ADSP audio",
            "usb_typec": "USB, DWC3, Type-C, PHYs, DisplayPort alt mode",
            "camera": "CAMSS, CCI, image sensors, actuators",
            "thermal_power": "Thermal, regulators, PMIC, charging, battery, clocks, power domains",
            "connectivity": "Modem, IPA, Wi-Fi, Bluetooth, NFC",
            "storage_mem": "UFS, MMC, memory, IOMMU/SMMU, interconnect",
            "board_other": "Device-tree or drivers for a specific other board",
            "tooling": "Build, debug-only or bring-up helpers not meant for normal use",
        },
    },
    "fixes_crash": {
        "type": "noul",
        "instructions": "Does this patch fix a crash, hang, SoC reset, kernel panic, GPU fault, or data corruption (as opposed to adding a feature, tuning, or cleanup)?",
        "criteria": {
            "true": "The commit message describes fixing a crash, hang, reset, panic, fault or corruption",
            "false": "It adds features, tunes behaviour, cleans up, or fixes only cosmetic/log issues",
        },
    },
}


def apply_status(path):
    def ok(*args):
        return subprocess.run(["git", "-C", TREE, "apply", "--check", *args, path],
                              capture_output=True).returncode == 0
    if ok():
        return "APPLIES"
    if ok("-R"):
        return "ALREADY-IN"
    return "CONFLICT"


def parse(path):
    text = open(path, errors="replace").read()
    subj = re.search(r"^Subject: (?:\[PATCH[^\]]*\] )?(.+(?:\n .+)*)", text, re.M)
    subject = re.sub(r"\s*\n\s+", " ", subj.group(1)).strip() if subj else os.path.basename(path)
    body = text.split("\n\n", 1)[1] if "\n\n" in text else ""
    msg = body.split("\n---\n", 1)[0]
    files = re.findall(r"^diff --git a/(\S+)", text, re.M)
    return subject, "\n".join(msg.splitlines()[:45]), files


def jev(state):
    req = urllib.request.Request(
        "https://api.typesafe.ai/v1/systemone",
        data=json.dumps({"model": "jev-latest", "state": state,
                         "questions": QUESTIONS}).encode(),
        headers={"Authorization": "Bearer " + os.environ["TYPESAFE_API_KEY"],
                 "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)["answers"]


def one(name):
    path = os.path.join(PATCHES, name)
    subject, msg, files = parse(path)
    status = apply_status(path)
    state = {"device": JOAN, "patch": {"subject": subject, "message": msg, "files": files}}
    try:
        a = jev(state)
        res = {"relevant": round(a["relevant"]["noul"], 3),
               "subsystem": a["subsystem"]["choice"],
               "subsystem_conf": round(a["subsystem"].get("confidence", 0), 3),
               "fixes_crash": round(a["fixes_crash"]["noul"], 3)}
    except Exception as e:  # keep going; record the failure
        res = {"error": str(e)}
    return {"patch": name, "subject": subject, "status": status, "files": files, **res}


names = sorted(n for n in os.listdir(PATCHES) if re.match(r"\d{4}-.*\.patch$", n))
with cf.ThreadPoolExecutor(8) as ex:
    rows = list(ex.map(one, names))
json.dump(rows, open(OUT, "w"), indent=1)
print(f"{len(rows)} patches, {sum('error' in r for r in rows)} errors")
