#!/bin/sh

set -eu

[ "$(uname -s)" = Darwin ] || {
	printf '%s\n' 'macos: skipped (not Darwin)'
	exit 0
}

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/df-macos.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

case "$(uname -m)" in
arm64) platform=macos-arm64 ;;
x86_64) platform=macos-x64 ;;
*)
	printf '%s\n' 'macos: unsupported architecture' >&2
	exit 1
	;;
esac

janet=$(mise which janet)
target_mise=$root/dist/runtime/bin/$platform/mise
home=$work/home

HOME=$home XDG_CONFIG_HOME=$home/.config XDG_DATA_HOME=$home/.local/share \
	XDG_STATE_HOME=$home/.local/state DF_JANET=$janet DF_MISE=$target_mise \
	"$root/ds" diff core >"$work/diff"
HOME=$home XDG_CONFIG_HOME=$home/.config XDG_DATA_HOME=$home/.local/share \
	XDG_STATE_HOME=$home/.local/state DF_JANET=$janet DF_MISE=$target_mise \
	"$root/ds" apply core --dry-run >"$work/apply"

[ ! -e "$home" ]
grep -q '^diff core:$' "$work/diff"
grep -q '^would apply core:$' "$work/apply"
zsh -n "$root/dotfiles/shell.zsh"

mkdir -p "$home"
HOME=$home XDG_CONFIG_HOME=$home/.config XDG_DATA_HOME=$home/.local/share \
	XDG_STATE_HOME=$home/.local/state MISE_CACHE_DIR=$home/.cache/mise \
	MISE_CONFIG_DIR=$home/.config/df/mise MISE_DATA_DIR=$home/.local/share/mise \
	MISE_STATE_DIR=$home/.local/state/mise MISE_SYSTEM_CONFIG_DIR=$home/.config/df/system \
	MISE_OVERRIDE_CONFIG_FILENAMES=mise.toml MISE_TRUSTED_CONFIG_PATHS=$root \
	MISE_ENV='' "$target_mise" -C "$root" bootstrap --yes --dry-run >"$work/bootstrap" 2>&1
grep -q 'brew' "$work/bootstrap"
if grep -q 'apk add\|apt-get install\|dnf install' "$work/bootstrap"; then
	printf '%s\n' 'macos: Linux package manager appeared in dry-run' >&2
	exit 1
fi

printf '%s\n' 'macos: ok'
