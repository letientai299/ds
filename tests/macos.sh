#!/bin/sh

set -eu

[ "$(uname -s)" = Darwin ] || {
	printf '%s\n' 'macos: skipped (not Darwin)'
	exit 0
}

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
# Resolved before isolation, which hides mise's trust records.
janet=$(mise which janet)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-macos.XXXXXX")
# shellcheck source=tests/isolate.sh
. "$(dirname -- "$0")/isolate.sh"
isolate_home "$work/isolated-home"
trap 'rm -rf "$work"' EXIT HUP INT TERM

case "$(uname -m)" in
arm64) platform=macos-arm64 ;;
x86_64) platform=macos-x64 ;;
*)
	printf '%s\n' 'macos: unsupported architecture' >&2
	exit 1
	;;
esac

target_mise=$root/dist/runtime/bin/$platform/mise
home=$work/home

HOME=$home XDG_CONFIG_HOME=$home/.config XDG_DATA_HOME=$home/.local/share \
	XDG_STATE_HOME=$home/.local/state DS_JANET=$janet DS_MISE=$target_mise \
	"$root/ds" diff core >"$work/diff"
HOME=$home XDG_CONFIG_HOME=$home/.config XDG_DATA_HOME=$home/.local/share \
	XDG_STATE_HOME=$home/.local/state DS_JANET=$janet DS_MISE=$target_mise \
	"$root/ds" apply core --dry-run >"$work/apply"

[ ! -e "$home" ]
grep -q '^diff core:$' "$work/diff"
grep -q '^would apply core:$' "$work/apply"
zsh -n "$root/src/dotfiles/shell.zsh"

mkdir -p "$home"
HOME=$home XDG_CONFIG_HOME=$home/.config XDG_DATA_HOME=$home/.local/share \
	XDG_STATE_HOME=$home/.local/state MISE_CACHE_DIR=$home/.cache/mise \
	MISE_CONFIG_DIR=$home/.config/ds/mise MISE_DATA_DIR=$home/.local/share/mise \
	MISE_STATE_DIR=$home/.local/state/mise MISE_SYSTEM_CONFIG_DIR=$home/.config/ds/system \
	MISE_OVERRIDE_CONFIG_FILENAMES=mise.toml MISE_TRUSTED_CONFIG_PATHS=$root/src/mise \
	MISE_ENV=core "$target_mise" -C "$root/src/mise" bootstrap --yes --dry-run >"$work/bootstrap" 2>&1
# Layers declare only Linux packages; macOS relies on mise-managed tools.
grep -q 'skipped (only available on linux)' "$work/bootstrap"
if grep -q 'apk add\|apt-get install\|dnf install' "$work/bootstrap"; then
	printf '%s\n' 'macos: Linux package manager appeared in dry-run' >&2
	exit 1
fi

printf '%s\n' 'macos: ok'
