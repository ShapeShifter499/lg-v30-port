# -*- coding: utf-8 -*-
# AnalyzeHexStrings.py — locate diagnostic strings in the merged ADSP
# firmware and list xrefs (Python/Jython, runs headless).
#@category ADSP.RE
#@menupath Tools.ADSP.FindIntentStrings

from ghidra.app.util.bin import MemoryByteProvider
from ghidra.program.model.mem import MemoryBlock
from ghidra.program.model.address import AddressSet
from ghidra.program.model.symbol import RefType

needles = [
    "Dropping intent req",
    "Could not notify RX Done",
    "Could not queue RX intent",
    "glink_core_intent.c",
    "IPCRTR",
    "slimbus_qmi",
]

mem = currentProgram.getMemory()
refs = currentProgram.getReferenceManager()

for needle in needles:
    print("=== searching: %s ===" % needle)
    addr = mem.findBytes(
        mem.getMinAddress(),
        needle.encode("utf-8"),
        None,
        True,
        monitor,
    )
    found = 0
    a = addr
    while a is not None and found < 30:
        found += 1
        print("  string @ %s" % a)
        rc = 0
        for r in refs.getReferencesTo(a):
            if rc >= 6:
                break
            print("    xref from %s" % r.getFromAddress())
            rc += 1
        a = mem.findBytes(a.add(1), needle.encode("utf-8"), None, True, monitor)
    print("  total: %d" % found)
