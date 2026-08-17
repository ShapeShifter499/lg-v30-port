# -*- coding: utf-8 -*-
# DecompileHex.py - decompile functions containing the glink intent
# machinery xref sites and dump the pseudo-C.
#@category ADSP.RE
#@menupath Tools.ADSP.DecompileIntent

from ghidra.app.decompiler import DecompInterface
from ghidra.util.task import ConsoleTaskMonitor

sites = [
    "f00f4744",   # Dropping intent req handler
    "f00f58cc",   # Could not notify RX Done
    "f00f61a4",   # Could not queue RX intent
    "f024aa08",   # IPCRTR registration (csi xport)
]

decomp = DecompInterface()
decomp.openProgram(currentProgram)
monitor = ConsoleTaskMonitor()

for s in sites:
    addr = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(s)
    func = getFunctionContaining(addr)
    if func is None:
        print("=== %s: no function found ===" % s)
        continue
    print("=== %s in %s @ %s ===" % (s, func.getName(), func.getEntryPoint()))
    res = decomp.decompileFunction(func, 60, monitor)
    if res is not None and res.decompileCompleted():
        c = res.getDecompiledFunction().getC()
        # print first 90 lines
        lines = c.split("\n")
        print("\n".join(lines[:90]))
    else:
        print("  decompile failed")
    print("")
