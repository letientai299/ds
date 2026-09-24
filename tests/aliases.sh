#!/bin/sh
set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-aliases.XXXXXX")
work=$(CDPATH='' cd -P "$work" && pwd)
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM

env -i HOME="$work/home" PATH="$PATH" TERM=dumb \
	zsh -dfis -- "${1:-$root/src/dotfiles/shell.zsh}" "$work" \
	<"$root/tests/aliases.zsh" >"$work/out" 2>"$work/err" || {
	cat "$work/out" "$work/err"
	exit 1
}
grep -qx 'aliases: ok' "$work/out"
printf '%s\n' 'aliases: ok'
