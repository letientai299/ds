#!/bin/sh

pull_repositories() {
	root=$1
	repo_command=$2
	extra=${3:-}
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
					printf '%s\n' "${repo_command}: skipping absent $name.conf"
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
	[ -z "$extra" ] || set -- "$@" "$extra"

	[ "$#" -eq 0 ] || command -v git >/dev/null 2>&1 || die 'git is required'

	for checkout in "$@"; do
		[ -d "$checkout/.git" ] || [ -f "$checkout/.git" ] || die "source requires a Git checkout: $checkout"
		git -C "$checkout" symbolic-ref -q HEAD >/dev/null || die "checkout has a detached HEAD: $checkout"
		status=$(git -C "$checkout" status --porcelain --untracked-files=normal)
		[ -z "$status" ] || die "checkout has uncommitted changes: $checkout"
		git -C "$checkout" rev-parse --verify '@{upstream}' >/dev/null 2>&1 || die "branch has no upstream: $checkout"
	done

	for checkout in "$@"; do
		printf '%s\n' "$repo_command: pulling $checkout"
		git -C "$checkout" -c merge.autostash=false -c rebase.autostash=false \
			pull --ff-only --no-rebase || return "$?"
	done
}
