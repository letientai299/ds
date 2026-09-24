#!/bin/sh
set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-activation.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM
mkdir -p "$work/home/.config/ds" "$work/one" "$work/two"
printf '[env]\nDS_TEST_PROJECT = "one"\n' >"$work/one/mise.toml"
printf '[env]\nDS_TEST_PROJECT = "two"\n' >"$work/two/mise.toml"
cat >"$work/home/.config/ds/local.zsh" <<'ZSH'
export MISE_TRUSTED_CONFIG_PATHS="$MISE_TRUSTED_CONFIG_PATHS:$DS_TEST_WORK"
ZSH
for enabled in 0 1; do
	env -i HOME="$work/home" PATH="$PATH" TERM=dumb \
		DS_SHELL_ROOT="$root" DS_TEST_SRC="${1:-$root/src}" DS_TEST_WORK="$work" \
		DS_MISE_ACTIVATE="$enabled" zsh -dfi "$root/tests/activation.zsh"
done
printf '%s\n' 'activation: ok'
