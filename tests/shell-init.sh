#!/bin/sh

set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-shell-test.XXXXXX")
# shellcheck source=tests/isolate.sh
. "$(dirname -- "$0")/isolate.sh"
isolate_home "$work/isolated-home"
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM

for version in first second; do
	mkdir -p "$work/prefix/versions/$version/src/scripts"
	mkdir -p "$work/prefix/versions/$version/src/dotfiles"
	cp "$root/ds" "$work/prefix/versions/$version/ds"
	cp "$root/src/dotfiles/command.sh" "$work/prefix/versions/$version/src/dotfiles/command.sh"
	printf '(defn main [& _args] (print "%s"))\n' "$version" \
		>"$work/prefix/versions/$version/src/scripts/main.janet"
done
ln -s versions/first "$work/prefix/current"
fragment=$(DS_ROOT="$work/prefix/versions/first" JANET_PATH="$root/src" \
	janet "$root/src/scripts/main.janet" shell-init)
HOME="$work/home" XDG_CONFIG_HOME="$work/home/config" \
	DS_ROOT="$work/prefix/versions/first" DS_JANET="$(command -v janet)" \
	sh -s -- "$fragment" "$work/prefix" <<'SH'
set -eu
eval "$1"
[ "$(ds status core)" = first ]
rm "$2/current"
ln -s versions/second "$2/current"
[ "$(ds status core)" = second ]
SH

cat >"$work/update" <<'SH'
#!/bin/sh
case "$1" in
update) exit "${DS_TEST_UPDATE_STATUS:-0}" ;;
shell-init) printf '%s\n' 'export DS_TEST_REFRESHED=yes' ;;
esac
SH
chmod +x "$work/update"
DS_DS="$work/update" sh -s -- "$root/src/dotfiles/command.sh" <<'SH'
set -eu
. "$1"
ds update
[ "$DS_TEST_REFRESHED" = yes ]
unset DS_TEST_REFRESHED
DS_TEST_UPDATE_STATUS=1 ds update && exit 1
[ -z "${DS_TEST_REFRESHED:-}" ]
SH

printf '%s\n' 'shell init: ok'
