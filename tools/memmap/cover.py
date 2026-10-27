import subprocess, sys
def regions(dtb):
    out = []
    for n in subprocess.run(["fdtget","-l",dtb,"/reserved-memory"],capture_output=True,text=True).stdout.split():
        r = subprocess.run(["fdtget","-tx",dtb,"/reserved-memory/"+n,"reg"],capture_output=True,text=True)
        if r.returncode: continue
        w=[int(x,16) for x in r.stdout.split()]
        out.append(((w[0]<<32)|w[1], ((w[0]<<32)|w[1])+((w[2]<<32)|w[3]), n))
    return sorted(out)
lg, ours = regions(sys.argv[1]), regions(sys.argv[2])
def covered(a,b,rs):
    gaps=[]; cur=a
    for s,e,_ in rs:
        if e<=cur or s>=b: continue
        if s>cur: gaps.append((cur,min(s,b)))
        cur=max(cur,e)
        if cur>=b: break
    if cur<b: gaps.append((cur,b))
    return gaps
bad=0
for s,e,n in lg:
    g=covered(s,e,ours)
    if g: bad+=1; print(f"LG {n} {s:#x}-{e:#x} NOT covered: "+", ".join(f"{x:#x}-{y:#x}" for x,y in g))
print("LG regions fully covered" if not bad else f"{bad} LG regions with gaps")
for s,e,n in ours:
    g=covered(s,e,lg)
    if g: print(f"ours-only {n}: "+", ".join(f"{x:#x}-{y:#x}" for x,y in g))
