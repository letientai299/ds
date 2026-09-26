#!/bin/sh

set -eu

die() {
	printf '%s\n' "ds update: $*" >&2
	exit 1
}

case "$#:${1:-}" in
1:-h | 1:--help)
	printf '%s\n' 'usage: ds update' \
		'Update ds and installed configuration source checkouts.' \
		'Includes nvim.conf, tmux.conf, and kitty.conf.' \
		'Honors DS_NVIM_SOURCE, DS_TMUX_SOURCE, and DS_KITTY_SOURCE.' \
		'Requires clean Git checkouts with tracked branches.' \
		'Run ds apply to apply updated configuration.'
	exit 0
	;;
0:) ;;
*) die "unexpected argument: $1" ;;
esac

root=$(CDPATH='' cd -P "$(dirname -- "$0")/../.." && pwd)
command -v git >/dev/null 2>&1 || die 'git is required'
[ -d "$root/.git" ] || [ -f "$root/.git" ] || die 'update requires a Git checkout'

set --
for name in nvim tmux kitty; do
	case "$name" in
	nvim) source=${DS_NVIM_SOURCE:-} ;;
	tmux) source=${DS_TMUX_SOURCE:-} ;;
	kitty) source=${DS_KITTY_SOURCE:-} ;;
	esac
	if [ -z "$source" ]; then
		source=$root/../$name.conf
		if [ ! -e "$source" ]; then
			printf '%s\n' "ds update: skipping absent $name.conf"
			continue
		fi
	fi
	[ -d "$source" ] || die "source is missing: $source"
	source=$(CDPATH='' cd -P "$source" && pwd)
	[ "$source" != "$root" ] || continue
	duplicate=false
	for checkout in "$@"; do
		[ "$checkout" != "$source" ] || duplicate=true
	done
	[ "$duplicate" = true ] || set -- "$@" "$source"
done
set -- "$@" "$root"

for checkout in "$@"; do
	[ -d "$checkout/.git" ] || [ -f "$checkout/.git" ] || die "source requires a Git checkout: $checkout"
	git -C "$checkout" symbolic-ref -q HEAD >/dev/null || die "checkout has a detached HEAD: $checkout"
	status=$(git -C "$checkout" status --porcelain --untracked-files=normal)
	[ -z "$status" ] || die "checkout has uncommitted changes: $checkout"
	git -C "$checkout" rev-parse --verify '@{upstream}' >/dev/null 2>&1 || die "branch has no upstream: $checkout"
done

for checkout in "$@"; do
	printf '%s\n' "ds update: pulling $checkout"
	# Self-update replaces this executing script.
	if [ "$checkout" = "$root" ]; then
		exec git -C "$checkout" -c merge.autostash=false -c rebase.autostash=false \
			pull --ff-only --no-rebase
	fi
	git -C "$checkout" -c merge.autostash=false -c rebase.autostash=false \
		pull --ff-only --no-rebase
done
