#!/bin/sh
set -eu
root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-layers.XXXXXX")
trap 'rm -rf "$work"' EXIT
fail() {
	printf '%s\n' "layers: $*" >&2
	exit 1
}
DS_JANET=$(command -v janet)
export DS_JANET HOME="$work/home" XDG_CONFIG_HOME="$work/home/config"
export XDG_DATA_HOME="$work/home/data" XDG_CACHE_HOME="$work/home/cache" XDG_STATE_HOME="$work/home/state"
export DS_MISE="$work/mise" DS_TEST_LOG="$work/profiles"
export DS_NVIM_SOURCE="$work/nvim" DS_TMUX_SOURCE="$work/tmux" DS_KITTY_SOURCE="$work/kitty"
unset DS_SHELL_STATE DS_SHELL_ROOT DS_SHELL_PATH ZDOTDIR
mkdir -p "$HOME" "$DS_NVIM_SOURCE" "$DS_TMUX_SOURCE" "$DS_KITTY_SOURCE/bin"
cat >"$DS_MISE" <<'MISE'
#!/bin/sh
printf '%s\n' "$MISE_ENV" >>"$DS_TEST_LOG"
MISE
printf '%s\n' '#!/bin/sh' 'exit 0' >"$DS_TMUX_SOURCE/tm"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$DS_KITTY_SOURCE/bin/kt"
chmod +x "$DS_MISE" "$DS_TMUX_SOURCE/tm" "$DS_KITTY_SOURCE/bin/kt"
"$root/ds" apply extra >/dev/null
[ "$(cat "$DS_TEST_LOG")" = extra ] || fail 'extra installed another profile'
[ ! -e "$HOME/.zshrc" ] && [ ! -e "$XDG_CONFIG_HOME/nvim" ] || fail 'extra installed core configuration'
"$root/ds" apply core >/dev/null
[ "$(cat "$XDG_CONFIG_HOME/ds/layer")" = extra,core ] || fail 'core discarded extra'
"$root/ds" status --json >"$work/status"
grep -q '"target":"extra,core"' "$work/status" || fail 'status omitted a layer'
"$root/ds" apply --dry-run >"$work/plan"
grep -q 'profile extra,core' "$work/plan" || fail 'apply omitted selected profiles'
"$root/ds" remove extra >/dev/null
[ -L "$XDG_CONFIG_HOME/nvim" ] || fail 'extra removal lost core files'
[ "$(cat "$XDG_CONFIG_HOME/ds/layer")" = core ] || fail 'extra removal lost selection'
"$root/ds" apply remote --skip docker >/dev/null
"$root/ds" remove core >/dev/null
[ -L "$XDG_CONFIG_HOME/nvim" ] || fail 'core removal lost shared files'
[ "$(cat "$XDG_CONFIG_HOME/ds/layer")" = remote ] || fail 'core removal lost remote'
"$root/ds" remove remote >/dev/null
[ ! -e "$XDG_CONFIG_HOME/nvim" ] || fail 'last removal left core files'
"$root/ds" apply ui >/dev/null
[ "$(tail -1 "$DS_TEST_LOG")" = ui ] || fail 'ui installed another profile'
[ ! -e "$XDG_CONFIG_HOME/nvim" ] || fail 'ui installed core configuration'
[ -L "$HOME/.local/bin/kt" ] || fail 'ui launcher missing'
"$root/ds" apply all --skip docker >/dev/null
"$root/ds" remove ui >/dev/null
[ ! -e "$HOME/.local/bin/kt" ] || fail 'ui removal left launcher'
[ -L "$XDG_CONFIG_HOME/nvim" ] || fail 'ui removal lost core'
"$root/ds" remove all >/dev/null
[ ! -e "$XDG_CONFIG_HOME/ds/layer" ] || fail 'all removal left selection'
: >"$DS_TEST_LOG"
if DS_LIBC=musl "$root/ds" apply all --skip docker >"$work/out" 2>"$work/err"; then fail 'musl accepted ui'; fi
grep -q 'Kitty requires macOS or glibc Linux' "$work/err" || fail 'musl reason missing'
[ ! -s "$DS_TEST_LOG" ] || fail 'musl rejection installed packages'
printf '%s\n' 'independent layers: ok'
