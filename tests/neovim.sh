#!/bin/sh

set -eu
root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-neovim.XXXXXX")
# shellcheck source=tests/isolate.sh
. "$root/tests/isolate.sh"
isolate_home "$work/home"
trap 'rm -rf "$work"' EXIT
fail() {
	printf '%s\n' "neovim: $*" >&2
	exit 1
}
DS_JANET=$(command -v janet)
export DS_JANET DS_MISE="$work/mise" DS_NVIM_SOURCE="$work/nvim"
export DS_TEST_LOG="$work/calls" DS_TEST_CONFIG="$XDG_CONFIG_HOME"
export NVIM_APPNAME=other
mkdir -p "$DS_NVIM_SOURCE/lua/lib"
printf '%s\n' 'return {}' >"$DS_NVIM_SOURCE/lua/lib/bootstrap.lua"
cat >"$DS_MISE" <<'SH'
#!/bin/sh
set -eu
[ "$3" = exec ] || exit 0
[ "$4" = -- ] && [ "$5" = nvim ] && [ "$6" = --headless ]
case "$7" in *"require('lib.bootstrap').run()"*) ;; *) exit 2 ;; esac
[ "$8" = '+qa!' ]
[ "$NVIM_APPNAME" = nvim ] && [ "$GIT_TERMINAL_PROMPT" = 0 ]
[ "$XDG_CONFIG_HOME" = "$DS_TEST_CONFIG" ]
[ -L "$XDG_CONFIG_HOME/nvim" ]
[ -f "$XDG_CONFIG_HOME/nvim/lua/lib/bootstrap.lua" ]
if read -r answer; then exit 3; fi
printf '%s\n' "$MISE_ENV" >>"$DS_TEST_LOG"
exit "${DS_TEST_EXIT:-0}"
SH
chmod +x "$DS_MISE"
"$root/ds" apply core --dry-run >"$work/plan"
grep -q 'bootstrap Neovim essential plugins' "$work/plan" || fail 'preview omitted bootstrap'
[ ! -e "$DS_TEST_LOG" ] || fail 'preview ran bootstrap'
"$root/ds" apply extra >/dev/null
[ ! -e "$DS_TEST_LOG" ] || fail 'extra ran bootstrap'
"$root/ds" apply core >/dev/null
[ "$(cat "$DS_TEST_LOG")" = core ] || fail 'core skipped bootstrap'
"$root/ds" apply core >/dev/null
[ "$(wc -l <"$DS_TEST_LOG" | tr -d ' ')" = 2 ] || fail 'reapply skipped bootstrap'
if DS_TEST_EXIT=9 "$root/ds" apply core >"$work/out" 2>"$work/err"; then
	fail 'bootstrap failure accepted'
fi
grep -q 'Neovim bootstrap failed with status 9' "$work/err" || fail 'bootstrap failure omitted'
"$root/ds" apply core >/dev/null
"$root/ds" remove core >/dev/null
[ "$(wc -l <"$DS_TEST_LOG" | tr -d ' ')" = 4 ] || fail 'removal ran bootstrap'
rm "$DS_NVIM_SOURCE/lua/lib/bootstrap.lua"
"$root/ds" apply core >/dev/null
[ "$(wc -l <"$DS_TEST_LOG" | tr -d ' ')" = 4 ] || fail 'custom config ran bootstrap'
candidate="$work/prefix/versions/first"
mkdir -p "$candidate"
cp "$root/ds" "$candidate/ds"
cp -R "$root/src" "$candidate/src"
mkdir -p "$candidate/src/vendor/nvim.conf/lua/lib"
printf '%s\n' 'return {}' >"$candidate/src/vendor/nvim.conf/lua/lib/bootstrap.lua"
unset DS_NVIM_SOURCE
isolate_home "$work/bundled-home"
export DS_TEST_CONFIG="$XDG_CONFIG_HOME"
"$candidate/ds" apply core >/dev/null
[ "$(readlink "$work/prefix/current")" = versions/first ] || fail 'bootstrap preceded activation'
[ "$(wc -l <"$DS_TEST_LOG" | tr -d ' ')" = 5 ] || fail 'snapshot skipped bootstrap'
printf '%s\n' 'neovim: ok'
