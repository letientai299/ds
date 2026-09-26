#!/bin/sh

set -eu

die() {
	printf '%s\n' "ds update: $*" >&2
	exit 1
}

case "$#:${1:-}" in
1:-h | 1:--help)
	printf '%s\n' 'usage: ds update' \
		'Update ds, configuration repos, runtimes, and selected layers.' \
		'Includes sibling and installed nvim.conf, tmux.conf, and kitty.conf.' \
		'Honors DS_NVIM_SOURCE, DS_TMUX_SOURCE, and DS_KITTY_SOURCE.' \
		'Requires clean Git checkouts with tracked branches.' \
		'Refresh runtimes and reapply selected layers automatically.'
	exit 0
	;;
0:) ;;
*) die "unexpected argument: $1" ;;
esac

source_only=${DS_UPDATE_SOURCE_ONLY:-false}
unset DS_UPDATE_SOURCE_ONLY

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
			config_home=${XDG_CONFIG_HOME:-$HOME/.config}
			case "$name" in
			kitty) installed=$config_home/ds/kitty ;;
			*) installed=$config_home/$name ;;
			esac
			if [ -L "$installed" ] && { [ -d "$installed/.git" ] || [ -f "$installed/.git" ]; }; then
				source=$installed
			else
				printf '%s\n' "ds update: skipping absent $name.conf"
				continue
			fi
		fi
	fi
	[ -d "$source" ] || die "source is missing: $source"
	source=$(CDPATH='' cd -P "$source" && pwd)
	case "$name" in
	nvim)
		DS_NVIM_SOURCE=$source
		export DS_NVIM_SOURCE
		;;
	tmux)
		DS_TMUX_SOURCE=$source
		export DS_TMUX_SOURCE
		;;
	kitty)
		DS_KITTY_SOURCE=$source
		export DS_KITTY_SOURCE
		;;
	esac
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

# Parse the continuation before replacing this script.
{
	for checkout in "$@"; do
		printf '%s\n' "ds update: pulling $checkout"
		git -C "$checkout" -c merge.autostash=false -c rebase.autostash=false \
			pull --ff-only --no-rebase
	done
	[ "$source_only" = false ] || exit 0
	DS_INSTALL_UPDATED_ROOT=$root exec sh "$root/scripts/install.sh"
}
