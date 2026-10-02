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

# shellcheck source=src/scripts/repos.sh
. "$root/src/scripts/repos.sh"

# Parse the continuation before replacing this script.
{
	pull_repositories "$root" 'ds update' "$root"
	[ "$source_only" = false ] || exit 0
	DS_INSTALL_UPDATED_ROOT=$root exec sh "$root/scripts/install.sh"
}
