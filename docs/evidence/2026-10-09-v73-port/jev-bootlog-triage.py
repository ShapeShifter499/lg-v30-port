#!/usr/bin/env python3
"""Triage joan boot-log warning/error lines with Jev (TypeSafe System One).

Usage: jev-bootlog-triage.py <new-log> [<baseline-log>]  > triage.tsv

Each unique line (timestamps and hex/numbers normalised) is asked two
questions over the same state: what kind of message it is (choice) and
whether it needs a kernel/DT/package change (noul).  Code keeps the policy:
lines absent from the baseline are flagged NEW whatever Jev says, and Jev's
answers only order the manual review, they never close an item.
"""
import json, os, re, sys, time, urllib.request

API = "https://api.typesafe.ai/v1/systemone"
KEY = os.environ["TYPESAFE_API_KEY"]

CATEGORIES = {
    "bootloader_firmware": "Comes from the bootloader, TrustZone or vendor firmware behaviour that the kernel only reports and cannot fix (e.g. image misaligned by the bootloader, firmware handover already happened)",
    "benign_driver_noise": "A driver reporting an expected condition on this hardware that does not lose any function (e.g. optional supply absent so a dummy is used, a mixer mux with no routed paths, an advertised-but-unsupported optional command)",
    "missing_description": "The device tree or board data is incomplete: a supply, clock, pin, board file or calibration that should be described for this phone is missing, so a function may run degraded",
    "functional_failure": "Something failed to probe, initialise, power on or run, so a hardware function is broken or degraded (errors like init failed, timeout, fault, -ENODEV/-EBUSY/-110 on a path that is used)",
    "debug_instrumentation": "Temporary debug or bring-up logging added by developers, not a real problem (e.g. lines tagged DEBUG/JOANDBG, out-of-tree debug module taint)",
}

def norm(line):
    line = re.sub(r"^\[\s*\d+\.\d+\]\s*", "", line.strip())
    line = re.sub(r"^\S+ \d+ \d\d:\d\d:\d\d \S+ ", "", line)          # journal prefix
    line = re.sub(r"0x[0-9a-fA-F]+", "0xN", line)
    line = re.sub(r"\b\d+\b", "N", line)
    return line

def lines(path):
    out = {}
    for raw in open(path, errors="replace"):
        raw = raw.rstrip("\n")
        if not raw.strip() or raw.startswith("#"):
            continue
        out.setdefault(norm(raw), raw)
    return out

def ask(state):
    body = {
        "model": "jev-latest",
        "state": state,
        "questions": {
            "kind": {
                "type": "choice",
                "instructions": "Classify the kernel/system log line in `line`, logged while booting postmarketOS on the LG V30 (Qualcomm MSM8998) with a mainline kernel. Use `context` for what the hardware and port are.",
                "criteria": CATEGORIES,
            },
            "needs_change": {
                "type": "noul",
                "instructions": "Would fixing or silencing the message in `line` require a change to the kernel driver, the device tree, or the device's packages (rather than being acceptable as is)?",
            },
        },
    }
    req = urllib.request.Request(API, data=json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {KEY}",
                                          "Content-Type": "application/json"})
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)["answers"]
        except urllib.error.HTTPError as e:
            if e.code in (429, 529, 500, 502, 503):
                time.sleep(2 ** attempt)
                continue
            raise
    raise RuntimeError("TypeSafe API kept failing")

def main():
    new = lines(sys.argv[1])
    base = lines(sys.argv[2]) if len(sys.argv) > 2 else {}
    context = ("LG V30 joan (MSM8998, Adreno 540, WCN3990 Wi-Fi/BT/FM, WCD9340 codec over SLIMbus, "
               "PMI8998 charger, IPA modem data, CAMSS cameras, Venus video). Mainline 7.3 kernel plus "
               "device-specific patches, booted via LG's LK bootloader with fastboot boot.")
    print("status\tkind\tconfidence\tneeds_change\tline")
    for key, raw in sorted(new.items()):
        a = ask({"line": raw, "context": context})
        status = "same" if key in base else "NEW"
        print(f"{status}\t{a['kind']['choice']}\t{a['kind']['confidence']:.2f}\t"
              f"{a['needs_change']['noul']:.2f}\t{raw}", flush=True)

if __name__ == "__main__":
    main()
