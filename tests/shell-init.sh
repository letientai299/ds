#!/bin/sh

set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-shell-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM

for version in first second; do
	mkdir -p "$work/prefix/versions/$version"
	printf '%s\n' '#!/bin/sh' "printf '%s\\n' $version" >"$work/prefix/versions/$version/ds"
	chmod 0755 "$work/prefix/versions/$version/ds"
done
ln -s versions/first "$work/prefix/current"
fragment=$(DS_ROOT="$work/prefix/versions/first" JANET_PATH="$root/src" \
	janet "$root/src/scripts/main.janet" shell-init)
HOME="$work/home" XDG_CONFIG_HOME="$work/home/config" sh -s -- "$fragment" "$work/prefix" <<'SH'
set -eu
eval "$1"
[ "$(ds status core)" = first ]
rm "$2/current"
ln -s versions/second "$2/current"
[ "$(ds status core)" = second ]
SH

printf '%s\n' 'shell init: ok'
