#!/usr/bin/env bash
# Patch the pmOS initramfs so boot-stage waits self-heal instead of
# wedging forever with no input path (no OTG keyboard; touch flooding
# errors). Applied to the ramdisk tree BEFORE repacking.
#
# Patches (all in init_functions.sh):
#  1. check_filesystem() fsck-fail wait: `while ! iskey ...; do :; done`
#     -> bounded 30s auto-continue (echoes the fsck rc for diagnosis).
#  2. debug_shell() continue wait: `while ! [ -e /tmp/continue_boot ]`
#     -> bounded 90s auto-continue.
#  3. fail_halt_boot() "Looping forever" -> bounded 15s auto-reboot to
#     the persistent OS.
set -euo pipefail
RD="${1:?usage: $0 <ramdisk-tree>}"

cd "$RD"
F=init_functions.sh
[[ -f "$F" ]] || { echo "init_functions.sh not found in $RD" >&2; exit 1; }
cp "$F" "$F.orig"

python3 - <<'PYEOF'
import re
f = 'init_functions.sh'
s = open(f).read()

# 1. fsck-fail key wait -> 30s auto-continue + rc echo
old1 = '''\t\t\te2fsck -p "$partition"
\t\t\tif [ $? -ge 4 ]; then
\t\t\t\tstatus="fail"
\t\t\tfi'''
new1 = '''\t\t\te2fsck -p "$partition"
\t\t\tfsck_rc=$?
\t\t\techo "fsck of $partition returned $fsck_rc"
\t\t\tif [ $fsck_rc -ge 4 ]; then
\t\t\t\tstatus="fail"
\t\t\tfi'''
assert old1 in s, "patch1 anchor not found"
s = s.replace(old1, new1)

old2 = '''\t\tsplash_set_warning "Filesystem needs manual repair (fsck) ($partition)\\nhttps://postmarketos.org/troubleshooting\\n\\nBoot anyways by pressing Volume-Up or Left-Shift..."
\t\twhile ! iskey KEY_LEFTSHIFT KEY_VOLUMEUP ; do
\t\t\t:
\t\tdone'''
new2 = '''\t\tsplash_set_warning "Filesystem needs manual repair (fsck) ($partition)\\nhttps://postmarketos.org/troubleshooting\\n\\nBoot anyways by pressing Volume-Up or Left-Shift..."
\t\t_fsck_deadline=$(( $(date +%s) + 30 ))
\t\twhile ! iskey KEY_LEFTSHIFT KEY_VOLUMEUP ; do
\t\t\tif [ "$(date +%s)" -gt "$_fsck_deadline" ]; then
\t\t\t\techo "fsck repair wait timed out; booting anyway"
\t\t\t\tbreak
\t\t\tfi
\t\t\tsleep 0.2
\t\tdone'''
assert old2 in s, "patch2 anchor not found"
s = s.replace(old2, new2)

# 2. debug shell continue wait -> 90s auto-continue
old3 = '''\t# wait until we get the signal to continue boot
\twhile ! [ -e /tmp/continue_boot ]; do
\t\tsleep 0.2
\t\tif [ -e /tmp/dump_logs ]; then
\t\t\trm -f /tmp/dump_logs
\t\t\texport_logs
\t\tfi
\tdone'''
new3 = '''\t# wait until we get the signal to continue boot (auto-continue after 90s)
\t_cont_deadline=$(( $(date +%s) + 90 ))
\twhile ! [ -e /tmp/continue_boot ]; do
\t\tsleep 0.2
\t\tif [ -e /tmp/dump_logs ]; then
\t\t\trm -f /tmp/dump_logs
\t\t\texport_logs
\t\tfi
\t\tif [ "$(date +%s)" -gt "$_cont_deadline" ]; then
\t\t\techo "Debug shell timed out; continuing boot"
\t\t\ttouch /tmp/continue_boot
\t\tfi
\tdone'''
assert old3 in s, "patch3 anchor not found"
s = s.replace(old3, new3)

# 3. fail_halt_boot infinite loop -> 15s auto-reboot
old4 = '''\tdebug_shell
\techo "Looping forever"
\twhile true; do
\t\tsleep 1
\tdone'''
new4 = '''\tdebug_shell
\techo "Boot failed; rebooting to persistent OS in 15s"
\tsleep 15
\treboot -f'''
assert old4 in s, "patch4 anchor not found"
s = s.replace(old4, new4)

open(f, 'w').write(s)
print("init_functions.sh patched (4/4)")
PYEOF

echo "=== verify patches present ==="
grep -c 'fsck repair wait timed out' "$F"
grep -c 'Debug shell timed out' "$F"
grep -c 'rebooting to persistent OS' "$F"
grep -c 'fsck_rc' "$F"
rm -f "$F.orig"
echo PATCH_OK
