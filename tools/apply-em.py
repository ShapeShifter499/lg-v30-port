#!/usr/bin/env python3
"""Insert opp-microwatt into msm8998.dtsi's CPU OPP tables from em.txt
(lines "<silver|gold> <hz> <uW>"). Each OPP node gets the line right after
its opp-hz. Fails if any OPP in the two tables is left without a value."""
import re, sys
dtsi, emfile = sys.argv[1], sys.argv[2]
em = {}
for line in open(emfile):
    cl, hz, uw = line.split()
    em[(cl, int(hz))] = int(uw)
src = open(dtsi).read().split("\n")
out, table, done = [], None, set()
for line in src:
    if "cpu0_opp_table: opp-table-cpu0 {" in line:
        table = "silver"
    elif "cpu4_opp_table: opp-table-cpu4 {" in line:
        table = "gold"
    elif table and line == "\t};":
        table = None
    out.append(line)
    m = re.match(r"(\t+)opp-hz = /bits/ 64 <(\d+)>;", line)
    if table and m:
        key = (table, int(m.group(2)))
        assert key in em, f"no power for {key}"
        out.append(f"{m.group(1)}opp-microwatt = <{em[key]}>;")
        done.add(key)
missing = set(em) - done
assert not missing, f"OPPs not found in dtsi: {sorted(missing)}"
open(dtsi, "w").write("\n".join(out))
print(f"inserted {len(done)} opp-microwatt values")
