#!/usr/bin/env bash
# Install the shared commit-msg hook into the repos several agents touch.
#
# Hooks live in .git/hooks, which is per-clone and never travels with a
# push, so every clone has to be told separately. This script does that
# from the tracked copy in scripts/hooks/ so the thing being enforced is
# reviewable in the repo rather than hidden in .git.
#
#   usage: install-git-hooks.sh [repo ...]        (defaults to the shared set)
#          install-git-hooks.sh --check [repo ...] report only, install nothing
#          install-git-hooks.sh --uninstall [repo ...]
#
# Existing hooks are never clobbered silently: if a different commit-msg
# is already there it is backed up alongside with a .pre-hookinstall
# suffix and the path is printed.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/hooks/commit-msg"
[[ -r "$SRC" ]] || { echo "missing $SRC"; exit 2; }

MODE=install
case "${1:-}" in
	--check)     MODE=check;     shift ;;
	--uninstall) MODE=uninstall; shift ;;
esac

if (( $# )); then
	REPOS=("$@")
else
	REPOS=(
		"$HOME/vibe-coding-projects/coding/lg-v30-port"
		"$HOME/vibe-coding-projects/coding/linux-mainline-v30"
		"$HOME/vibe-coding-projects/coding/linux-mainline-v30-aurel-a184-polish"
	)
fi

rc=0
for repo in "${REPOS[@]}"; do
	name="$(basename "$repo")"
	if [[ ! -d "$repo" ]]; then
		printf '  %-46s SKIP (not present)\n' "$name"; continue
	fi
	hooks="$(git -C "$repo" rev-parse --git-path hooks 2>/dev/null)"
	if [[ -z "$hooks" ]]; then
		printf '  %-46s SKIP (not a git repo)\n' "$name"; continue
	fi
	# rev-parse --git-path may be relative to the repo
	[[ "$hooks" = /* ]] || hooks="$repo/$hooks"
	dst="$hooks/commit-msg"

	case "$MODE" in
	check)
		if [[ -x "$dst" ]] && cmp -s "$SRC" "$dst"; then
			printf '  %-46s OK (current)\n' "$name"
		elif [[ -e "$dst" ]]; then
			printf '  %-46s STALE or foreign hook installed\n' "$name"; rc=1
		else
			printf '  %-46s MISSING\n' "$name"; rc=1
		fi
		;;
	uninstall)
		if [[ -e "$dst" ]] && cmp -s "$SRC" "$dst"; then
			rm -f "$dst"; printf '  %-46s removed\n' "$name"
		elif [[ -e "$dst" ]]; then
			printf '  %-46s left alone (not our hook)\n' "$name"
		else
			printf '  %-46s nothing to remove\n' "$name"
		fi
		;;
	install)
		mkdir -p "$hooks"
		if [[ -e "$dst" ]] && ! cmp -s "$SRC" "$dst"; then
			bak="$dst.pre-hookinstall.$(date +%Y%m%d%H%M%S)"
			cp -p "$dst" "$bak"
			printf '  %-46s existing hook backed up -> %s\n' "$name" "$bak"
		fi
		install -m 0755 "$SRC" "$dst"
		printf '  %-46s installed\n' "$name"
		;;
	esac
done
exit $rc
