import subprocess, sys
def get(dtb, path, prop, typ="x"):
    r = subprocess.run(["fdtget", "-t", typ, dtb, path, prop], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None
def props(dtb, path):
    r = subprocess.run(["fdtget", "-p", dtb, path], capture_output=True, text=True)
    return r.stdout.split()
def dump(dtb):
    nodes = subprocess.run(["fdtget", "-l", dtb, "/reserved-memory"], capture_output=True, text=True).stdout.split()
    out = []
    for n in nodes:
        p = "/reserved-memory/" + n
        pr = props(dtb, p)
        reg = get(dtb, p, "reg")
        size = get(dtb, p, "size")
        ar = get(dtb, p, "alloc-ranges")
        flags = [f for f in ("no-map", "reusable") if f in pr]
        comp = get(dtb, p, "compatible", "s")
        def q(v):
            if not v: return None
            w = [int(x, 16) for x in v.split()]
            return w
        r = q(reg)
        if r:
            base = (r[0] << 32) | r[1]; sz = (r[2] << 32) | r[3]
            out.append((base, sz, n, " ".join(flags), comp or "", "fixed"))
        else:
            s = q(size); a = q(ar)
            sz = ((s[0] << 32) | s[1]) if s and len(s) == 2 else (s[0] if s else 0)
            rng = f"alloc {a[1]:#x}+{a[3]:#x}" if a and len(a) >= 4 else ""
            out.append((-1, sz, n, " ".join(flags), comp or "", "dynamic " + rng))
    for base, sz, n, fl, comp, kind in sorted(out):
        b = f"{base:#012x}" if base >= 0 else "     dyn    "
        e = f"{base+sz:#012x}" if base >= 0 else ""
        print(f"{b} {e:13} {sz:#10x} {n:40} {fl:16} {comp:28} {kind}")
dump(sys.argv[1])
