#!/usr/bin/env bash
# Host-only repo health check: no device, no network, no kernel tree.
#
#   scripts/check.sh
#
# 1. every shell script parses (bash -n / sh -n)
# 2. shellcheck at warning level, when shellcheck is installed
# 3. the device-side Python helper compiles
# 4. docs do not point at repo files that do not exist:
#    - relative Markdown links  [text](path)
#    - repo paths in prose/code: docs/..., scripts/..., tools/...
#    Evidence under out/ is local-only by design and is not checked.
#
# Exit 0 = clean, 1 = something needs fixing.
set -uo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
cd "$ROOT" || exit 2
rc=0
fail() { echo "  FAIL: $*"; rc=1; }

mapfile -t BASH_SCRIPTS < <(git ls-files '*.sh' scripts/hooks/commit-msg)
SH_SCRIPTS=(initramfs/root/init initramfs/root-null/init device/etc/init.d/joan-bt-address)

echo "== syntax =="
for f in "${BASH_SCRIPTS[@]}"; do bash -n "$f" || fail "$f"; done
for f in "${SH_SCRIPTS[@]}"; do sh -n "$f" || fail "$f"; done

echo "== shellcheck =="
if command -v shellcheck >/dev/null; then
	shellcheck -S warning "${BASH_SCRIPTS[@]}" || fail "shellcheck (bash scripts)"
	# busybox init: `ls | grep` is deliberate there (no find -maxdepth games
	# worth the risk in a device-proven init).
	shellcheck -s sh -S warning -e SC2010 initramfs/root/init initramfs/root-null/init ||
		fail "shellcheck (initramfs init)"
else
	echo "  skipped (shellcheck not installed)"
fi

echo "== python =="
python3 - device/usr/local/sbin/joan-bt-address <<'PY' || fail "joan-bt-address does not compile"
import sys
compile(open(sys.argv[1]).read(), sys.argv[1], "exec")
PY

echo "== doc references =="
python3 - <<'PY' || rc=1
import os, re, subprocess, sys

files = subprocess.run(["git", "ls-files", "*.md", "*.sh", "*.c"],
                       capture_output=True, text=True).stdout.split()
bad = []
link = re.compile(r"\]\(([^)#\s]+)")
path = re.compile(r"(?<![\w/.-])((?:docs|scripts|tools|initramfs|device)/[\w./*-]+\.(?:config|patch|dtsi|md|sh|c))(?![\w])")
for f in files:
    text = open(f, errors="replace").read()
    base = os.path.dirname(f)
    for m in (link.finditer(text) if f.endswith(".md") else ()):
        t = m.group(1)
        if re.match(r"^[a-z]+:", t):
            continue
        if not os.path.exists(os.path.join(base, t)):
            bad.append(f"{f}: link -> {t}")
    for m in path.finditer(text):
        t = m.group(1)
        if "*" in t or "<" in t:
            continue
        if not os.path.exists(t):
            line = text.count("\n", 0, m.start()) + 1
            # Explicitly annotated as never published: allowed.
            ctx = text[m.end():m.end() + 80]
            if "never published" in ctx:
                continue
            bad.append(f"{f}:{line}: path -> {t}")
for b in bad:
    print("  FAIL:", b)
sys.exit(1 if bad else 0)
PY

(( rc == 0 )) && echo "RESULT: PASS" || echo "RESULT: FAIL"
exit $rc
