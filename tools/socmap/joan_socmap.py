#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Map the LG V30 (joan) SoC blocks: downstream device tree vs mainline.

For every block, list what each tree gives it -- register ranges, clocks
(with downstream rates), supplies and power domains, bus-bandwidth votes
(downstream msm-bus vectors vs mainline interconnects), IOMMU stream IDs and
interrupts -- and flag what mainline lacks.

Inputs are flattened device trees, so what is compared is exactly what each
kernel boots with:
  --ds   the downstream DTB (e.g. /sys/firmware/fdt pulled from LineageOS on
         the phone, which boots LineageOS/android_kernel_lge_msm8998)
  --ml   the mainline DTB (arch/arm64/boot/dts/qcom/msm8998-lge-joan.dtb)
  --ds-tree / --ml-tree  kernel source trees, for the dt-bindings headers
         that turn clock, power-domain and bus IDs back into names.

  joan_socmap.py --ds ds.dtb --ml ml.dtb --ds-tree LG --ml-tree MAINLINE \
      --json out.json --md out.md
"""
import argparse
import json
import re
import struct
from collections import defaultdict
from pathlib import Path

# ---------------------------------------------------------------- FDT parsing

FDT_BEGIN_NODE, FDT_END_NODE, FDT_PROP, FDT_NOP, FDT_END = 1, 2, 3, 4, 9


class Node:
    def __init__(self, name, parent):
        self.name, self.parent = name, parent
        self.props, self.children = {}, []

    @property
    def path(self):
        if self.parent is None:
            return '/'
        pp = self.parent.path
        return (pp if pp != '/' else '') + '/' + self.name

    def u32s(self, prop):
        v = self.props.get(prop)
        if v is None:
            return None
        return list(struct.unpack('>%dI' % (len(v) // 4), v[:len(v) // 4 * 4]))

    def strs(self, prop):
        v = self.props.get(prop)
        if v is None:
            return None
        return [s.decode('latin-1') for s in v.split(b'\0')[:-1]] if v.endswith(b'\0') else [v.decode('latin-1')]

    def cells(self, prop, default):
        v = self.u32s(prop)
        return v[0] if v else default


def parse_fdt(path):
    b = Path(path).read_bytes()
    magic, _tot, off_struct, off_strings = struct.unpack_from('>IIII', b, 0)
    assert magic == 0xd00dfeed, f'{path}: not a DTB'

    def string(o):
        e = b.index(b'\0', off_strings + o)
        return b[off_strings + o:e].decode()

    i, root, cur = off_struct, None, None
    while True:
        tok, = struct.unpack_from('>I', b, i)
        i += 4
        if tok == FDT_BEGIN_NODE:
            e = b.index(b'\0', i)
            n = Node(b[i:e].decode(), cur)
            if cur is None:
                root = n
            else:
                cur.children.append(n)
            cur = n
            i = (e + 1 + 3) & ~3
        elif tok == FDT_END_NODE:
            cur = cur.parent
        elif tok == FDT_PROP:
            ln, nameoff = struct.unpack_from('>II', b, i)
            i += 8
            cur.props[string(nameoff)] = b[i:i + ln]
            i = (i + ln + 3) & ~3
        elif tok == FDT_NOP:
            continue
        elif tok == FDT_END:
            break
    return root


def walk(n):
    yield n
    for c in n.children:
        yield from walk(c)


def phandles(root):
    m = {}
    for n in walk(root):
        for p in ('phandle', 'linux,phandle'):
            if p in n.props:
                m[n.u32s(p)[0]] = n
    return m


def regs(n):
    """(base, size) pairs of a node's reg, in its parent's address space."""
    r = n.u32s('reg')
    if not r or n.parent is None:
        return []
    ac, sc = n.parent.cells('#address-cells', 2), n.parent.cells('#size-cells', 1)
    if ac == 0 or ac + sc == 0:
        return []
    out = []
    for k in range(0, len(r) - (ac + sc) + 1, ac + sc):
        a = 0
        for x in r[k:k + ac]:
            a = (a << 32) | x
        s = 0
        for x in r[k + ac:k + ac + sc]:
            s = (s << 32) | x
        out.append((a, s))
    return out


def in_soc(n):
    """Only memory-mapped SoC blocks: a reg in 0x0..0x20000000 under a bus."""
    p, anc = n.parent, []
    while p is not None:
        anc.append(p.name)
        p = p.parent
    if not any(a.startswith('soc') for a in anc):
        return False
    # children indexed by reg (ports, levels, channels) sit under a parent
    # with #size-cells = 0; MSM8998 peripherals start at 0x100000
    if n.parent.cells('#size-cells', 1) < 1:
        return False
    rr = regs(n)
    return bool(rr) and all(0x100000 <= a < 0x20000000 and s > 0 for a, s in rr)


def phandle_args(n, prop, ph, cells_prop, default_cells=1):
    """Decode <&prov a b &prov c ...> into (provider node, [args])."""
    v = n.u32s(prop)
    out, i = [], 0
    while v and i < len(v):
        prov = ph.get(v[i])
        if prov is None:
            out.append((None, [v[i]]))
            i += 1
            continue
        nc = prov.cells(cells_prop, default_cells)
        out.append((prov, v[i + 1:i + 1 + nc]))
        i += 1 + nc
    return out

# ------------------------------------------------------------ header lookups


def read_defines(path):
    d = {}
    try:
        txt = Path(path).read_text(errors='replace')
    except OSError:
        return d
    for name, val in re.findall(r'^#define\s+(\w+)\s+(\(?-?(?:0x[0-9a-fA-F]+|\d+)\)?)', txt, re.M):
        d[name] = int(val.strip('()'), 0)
    return d


def reverse(defs, pattern=None):
    """value -> names, real names first: range markers such as
    MSM_BUS_SLAVE_FIRST share a value with the first real ID."""
    r = defaultdict(list)
    for k, v in defs.items():
        if pattern is None or re.match(pattern, k):
            r[v].append(k)
    for v in r:
        r[v].sort(key=lambda k: bool(re.search(r'_(FIRST|LAST|INT_FIRST|INT_LAST)$', k)))
    return r

# ------------------------------------------------------------ normalisation


def core(name):
    """Tree-neutral clock/supply token: 'clk_mmss_camss_ahb_clk' and
    'CAMSS_AHB_CLK' both become 'camss_ahb'."""
    s = name.lower()
    s = re.sub(r'^(clk_|mmss_|gcc_|gpucc_|mmcc_)+', '', s)
    s = re.sub(r'(_clk|_clk_src|_src|_a)$', '', s)
    s = re.sub(r'^mmss_', '', s)
    return s

# ------------------------------------------------------------ per-tree model


class Tree:
    def __init__(self, dtb, src, kind):
        self.kind = kind
        self.root = parse_fdt(dtb)
        self.ph = phandles(self.root)
        self.src = Path(src) if src else None
        self.clkname = {}      # (provider compatible key, id) -> name
        self.busname = {}
        if kind == 'ds' and self.src:
            h = self.src / 'include/dt-bindings/clock'
            rev = {}
            for f in ('msm-clocks-8998.h', 'msm-clocks-hwio-8998.h'):
                for k, v in read_defines(h / f).items():
                    if k.startswith('clk_'):
                        rev.setdefault(v, k)
            self.ds_clk = rev
            b = read_defines(self.src / 'include/dt-bindings/msm/msm-bus-ids.h')
            self.ds_master = reverse(b, r'MSM_BUS_(MASTER|MAS)_')
            self.ds_slave = reverse(b, r'MSM_BUS_(SLAVE|SLV)_')
        if kind == 'ml' and self.src:
            hb = self.src / 'include/dt-bindings'
            self.ml_hdr = {
                'gcc': reverse(read_defines(hb / 'clock/qcom,gcc-msm8998.h')),
                'mmcc': reverse(read_defines(hb / 'clock/qcom,mmcc-msm8998.h')),
                'gpucc': reverse(read_defines(hb / 'clock/qcom,gpucc-msm8998.h')),
                'rpmcc': reverse(read_defines(hb / 'clock/qcom,rpmcc.h')),
                'icc': reverse(read_defines(hb / 'interconnect/qcom,msm8998.h')),
                'rpmpd': reverse(read_defines(hb / 'power/qcom-rpmpd.h')),
            }

    # -- names
    def prov_key(self, prov):
        c = ' '.join(prov.strs('compatible') or [prov.name]) if prov else '?'
        for k in ('gcc', 'mmcc', 'gpucc', 'rpmcc', 'rpmpd'):
            if re.search(rf'qcom,(msm8998-)?{k}|{k}-msm8998|qcom,{k}', c):
                return k
        if prov is not None and 'rpm' in c and 'clk' in c:
            return 'rpmcc'
        return prov.name if prov is not None else '?'

    def clock_name(self, prov, args):
        if self.kind == 'ds':
            if args:
                return self.ds_clk.get(args[0], f'{prov.name if prov else "?"}:{args[0]:#x}')
            return prov.name if prov else '?'
        key = self.prov_key(prov)
        names = self.ml_hdr.get(key, {}).get(args[0]) if args else None
        if names:
            return names[0]
        return f'{prov.name if prov else "?"}:{args[0] if args else ""}'

    # -- block model
    def block(self, n):
        d = {'path': n.path, 'compatible': n.strs('compatible') or [],
             'status': (n.strs('status') or ['okay'])[0],
             'reg': [(hex(a), hex(s)) for a, s in regs(n)]}
        rn = n.strs('reg-names')
        if rn:
            d['reg-names'] = rn
        cl = phandle_args(n, 'clocks', self.ph, '#clock-cells')
        if cl:
            names = n.strs('clock-names') or []
            rates = n.u32s('qcom,clock-rates') or []
            d['clocks'] = []
            for k, (prov, args) in enumerate(cl):
                e = {'id': self.clock_name(prov, args)}
                if k < len(names):
                    e['name'] = names[k]
                if k < len(rates) and rates[k]:
                    e['rate'] = rates[k]
                d['clocks'].append(e)
        ar = phandle_args(n, 'assigned-clocks', self.ph, '#clock-cells')
        if ar:
            rates = n.u32s('assigned-clock-rates') or []
            d['assigned'] = [{'id': self.clock_name(p, a), 'rate': rates[k] if k < len(rates) else None}
                             for k, (p, a) in enumerate(ar)]
        sup = {}
        for p in n.props:
            if p.endswith('-supply'):
                v = n.u32s(p)
                t = self.ph.get(v[0]) if v else None
                sup[p[:-7]] = (t.strs('regulator-name') or [t.name])[0] if t is not None else '?'
        if sup:
            d['supplies'] = sup
        pd = phandle_args(n, 'power-domains', self.ph, '#power-domain-cells')
        if pd:
            out = []
            for prov, args in pd:
                key = self.prov_key(prov) if self.kind == 'ml' else (prov.name if prov else '?')
                nm = None
                if self.kind == 'ml' and args:
                    hdr = self.ml_hdr.get(key if key != 'rpmpd' else 'rpmpd', {})
                    nm = (hdr.get(args[0]) or [None])[0]
                out.append(nm or f'{prov.name if prov else "?"}:{args}')
            d['power-domains'] = out
        # bus votes
        if self.kind == 'ds' and 'qcom,msm-bus,vectors-KBps' in n.props:
            v = n.u32s('qcom,msm-bus,vectors-KBps')
            npaths = n.cells('qcom,msm-bus,num-paths', 1)
            cases = []
            for k in range(0, len(v) - 3, 4):
                src, dst, ab, ib = v[k:k + 4]
                cases.append({'src': (self.ds_master.get(src) or [str(src)])[0],
                              'dst': (self.ds_slave.get(dst) or [str(dst)])[0],
                              'ab_KBps': ab, 'ib_KBps': ib})
            d['bus'] = {'name': (n.strs('qcom,msm-bus,name') or ['?'])[0],
                        'paths': npaths, 'vectors': cases}
        if self.kind == 'ml' and 'interconnects' in n.props:
            ic = phandle_args(n, 'interconnects', self.ph, '#interconnect-cells')
            names = n.strs('interconnect-names') or []
            flat = []
            for prov, args in ic:
                nm = (self.ml_hdr['icc'].get(args[0]) or [str(args[0])]) if args else ['?']
                flat.append(f'{prov.name if prov else "?"}:{"/".join(nm)}')
            d['interconnects'] = [{'name': names[k // 2] if k // 2 < len(names) else None,
                                   'src': flat[k], 'dst': flat[k + 1] if k + 1 < len(flat) else None}
                                  for k in range(0, len(flat), 2)]
        io = phandle_args(n, 'iommus', self.ph, '#iommu-cells')
        if io:
            d['iommus'] = [f'{p.name if p else "?"}:' + ','.join(hex(a) for a in args) for p, args in io]
        irq = n.u32s('interrupts') or n.u32s('interrupts-extended')
        if irq:
            d['n_interrupts'] = len(irq) // max(1, (n.parent.cells('#interrupt-cells', 3) if n.parent else 3))
        return d

    def soc_blocks(self):
        return [n for n in walk(self.root) if in_soc(n)]

# ------------------------------------------------------------ comparison


def overlap(r1, r2):
    return any(a1 < a2 + s2 and a2 < a1 + s1 for a1, s1 in r1 for a2, s2 in r2)


def compare(ds, ml):
    mlb = [(n, regs(n)) for n in ml.soc_blocks()]
    rows = []
    for n in ds.soc_blocks():
        r = regs(n)
        base = r[0][0]
        # first choice: mainline nodes whose ranges contain the downstream
        # node's first register base; otherwise any overlap
        hits = [m for m, mr in mlb if any(a <= base < a + s for a, s in mr)]
        if not hits:
            hits = [m for m, mr in mlb if overlap(r, mr)]
        # prefer the most specific mainline node (smallest total reg size)
        hits.sort(key=lambda m: sum(s for a, s in regs(m)))
        dsb = ds.block(n)
        mlbk = [ml.block(m) for m in hits[:2]]
        rows.append({'ds': dsb, 'ml': mlbk, 'findings': findings(dsb, mlbk)})
    return rows


def findings(d, ms):
    f = []
    if not ms:
        f.append('no mainline node covers this address range')
        return f
    m = ms[0]
    if d['status'] in ('okay', 'ok') and m['status'] == 'disabled':
        f.append('enabled downstream, disabled in mainline')
    dcl = {core(c['id']) for c in d.get('clocks', [])}
    mcl = set()
    for mm in ms:
        mcl |= {core(c['id']) for c in mm.get('clocks', [])}
    miss = sorted(x for x in dcl - mcl if x)
    if miss:
        f.append('clocks downstream only: ' + ', '.join(miss))
    if 'bus' in d and d['bus']['vectors'] and not any('interconnects' in mm for mm in ms):
        peak = max((v['ib_KBps'] for v in d['bus']['vectors']), default=0)
        f.append(f"downstream votes bus bandwidth ({d['bus']['name']}, peak ib {peak} KB/s); mainline node has no interconnects")
    dsup = set(d.get('supplies', {}))
    msup = set()
    for mm in ms:
        msup |= set(mm.get('supplies', {}))
    if dsup - msup:
        f.append('supplies downstream only: ' + ', '.join(sorted(dsup - msup)))
    if d.get('iommus') and not any(mm.get('iommus') for mm in ms):
        f.append('downstream has IOMMU stream IDs, mainline none')
    return f


DEBUG_RE = re.compile(r'^(cti|tpdm|tpda|funnel|replicator|tmc|etm|stm|hwevent|dcc|csr|'
                      r'qcom,coresight|jtagmm|modem_etm|audio_etm|rpm_etm|debug)')


def reserved(tree):
    rm = [n for n in tree.root.children if n.name == 'reserved-memory']
    out = []
    for r in rm:
        for c in r.children:
            rr = regs(c)
            sz = c.u32s('size')
            out.append({'name': c.name, 'reg': [(hex(a), hex(s)) for a, s in rr],
                        'size': hex(sz[-1]) if sz and not rr else None,
                        'no-map': 'no-map' in c.props,
                        'compatible': (c.strs('compatible') or [''])[0]})
    return out


def to_md(rows, out, ds=None, ml=None):
    lines = ['# joan SoC map: downstream vs mainline device tree', '',
             'Generated by `tools/socmap/joan_socmap.py`. One row per downstream '
             'memory-mapped block; the mainline node(s) are matched by overlapping '
             'register ranges. "Findings" are mechanical: a clock or supply only '
             'downstream may be named differently or handled by a driver, so each '
             'is a lead to check, not a verdict.', '']
    dbg = [r for r in rows if DEBUG_RE.match(r['ds']['path'].split('/')[-1])]
    rows = [r for r in rows if r not in dbg]
    lines += [f'CoreSight/debug blocks left out of the table: {len(dbg)} '
              '(trace funnels, CTIs, TPDM/TPDA, ETMs; not needed for a user build).', '']
    flagged = [r for r in rows if r['findings'] and r['ds']['status'] in ('okay', 'ok')]
    lines += [f'Downstream enabled blocks: {sum(1 for r in rows if r["ds"]["status"] in ("okay", "ok"))}; '
              f'with findings: {len(flagged)}; with no mainline node: '
              f'{sum(1 for r in flagged if "no mainline node" in r["findings"][0])}.', '']
    lines += ['| Downstream node | Base | Mainline node | Findings |', '|---|---|---|---|']
    for r in sorted(flagged, key=lambda r: int(r['ds']['reg'][0][0], 16)):
        mln = r['ml'][0]['path'].split('/')[-1] if r['ml'] else '—'
        lines.append(f"| `{r['ds']['path'].split('/')[-1]}` | {r['ds']['reg'][0][0]} | `{mln}` | "
                     + '<br>'.join(x.replace('|', '/') for x in r['findings']) + ' |')
    lines += ['', '## Bus-bandwidth votes (downstream msm-bus)', '',
              '| Client | Node | Vectors (src -> dst: ab/ib KB/s, per use case) | Mainline interconnects |',
              '|---|---|---|---|']
    for r in rows:
        b = r['ds'].get('bus')
        if not b:
            continue
        vec = '; '.join(f"{v['src'].replace('MSM_BUS_', '')}->{v['dst'].replace('MSM_BUS_', '')}: {v['ab_KBps']}/{v['ib_KBps']}"
                        for v in b['vectors'][:6])
        if len(b['vectors']) > 6:
            vec += f' ... ({len(b["vectors"])} vectors)'
        mi = ', '.join(i['name'] or '?' for m in r['ml'] for i in m.get('interconnects', [])) or '**none**'
        lines.append(f"| {b['name']} | `{r['ds']['path'].split('/')[-1]}` | {vec} | {mi} |")
    if ds is not None and ml is not None:
        def rng(x):
            return (int(x['reg'][0][0], 16), int(x['reg'][0][1], 16)) if x['reg'] else None
        dsr, mlr = reserved(ds), reserved(ml)

        def table(title, mine, other, other_name):
            out = ['', f'### {title}', '',
                   f'| Region | Start | End | Size | no-map | Overlaps in {other_name} |',
                   '|---|---|---|---|---|---|']
            for x in sorted(mine, key=lambda x: rng(x) or (1 << 40, 0)):
                r = rng(x)
                if r:
                    ov = [y['name'] for y in other if rng(y) and overlap([r], [rng(y)])]
                    out.append(f"| `{x['name']}` | {r[0]:#010x} | {r[0] + r[1] - 1:#010x} | "
                               f"{r[1] >> 10} KiB | {'yes' if x['no-map'] else ''} | "
                               f"{', '.join('`' + o + '`' for o in ov) or '**none**'} |")
                else:
                    out.append(f"| `{x['name']}` | dynamic | | {int(x['size'], 16) >> 10 if x['size'] else '?'} KiB | | |")
            return out
        lines += ['', '## Reserved memory (carve-outs)', '',
                  'Firmware loads to fixed addresses that the bootloader and TrustZone '
                  'expect, so a region at a different address in mainline is only '
                  'fine if that firmware is loaded by address from the DT. Check each '
                  '**none** and each partial overlap.']
        lines += table('Downstream (LineageOS kernel on this phone)', dsr, mlr, 'mainline')
        lines += table('Mainline (msm8998-lge-joan.dtb)', mlr, dsr, 'downstream')
    Path(out).write_text('\n'.join(lines) + '\n')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--ds', required=True)
    ap.add_argument('--ml', required=True)
    ap.add_argument('--ds-tree')
    ap.add_argument('--ml-tree')
    ap.add_argument('--json')
    ap.add_argument('--md')
    a = ap.parse_args()
    ds, ml = Tree(a.ds, a.ds_tree, 'ds'), Tree(a.ml, a.ml_tree, 'ml')
    rows = compare(ds, ml)
    if a.json:
        Path(a.json).write_text(json.dumps(rows, indent=1))
    if a.md:
        to_md(rows, a.md, ds, ml)
    en = [r for r in rows if r['ds']['status'] in ('okay', 'ok')]
    print(f'downstream SoC blocks {len(rows)} (enabled {len(en)}), '
          f'enabled with findings {sum(1 for r in en if r["findings"])}')


if __name__ == '__main__':
    main()
