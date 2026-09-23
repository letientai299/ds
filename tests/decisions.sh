#!/bin/sh

set -eu
root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-decisions.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM
fail() {
	printf '%s\n' "decisions: $*" >&2
	exit 1
}
jq_home=$HOME
jq_config=${XDG_CONFIG_HOME:-$HOME/.config}
jq_data=${XDG_DATA_HOME:-$HOME/.local/share}
jq_state=${XDG_STATE_HOME:-$HOME/.local/state}
jq_cache=${XDG_CACHE_HOME:-$HOME/.cache}
jq_mise=${MISE_DATA_DIR:-$jq_data/mise}
check_json() {
	HOME=$jq_home XDG_CONFIG_HOME=$jq_config XDG_DATA_HOME=$jq_data \
		XDG_STATE_HOME=$jq_state XDG_CACHE_HOME=$jq_cache MISE_DATA_DIR=$jq_mise \
		command jq "$@"
}
export HOME="$work/home" XDG_CONFIG_HOME="$work/home/config"
export XDG_DATA_HOME="$work/home/data" XDG_STATE_HOME="$work/home/state"
export XDG_CACHE_HOME="$work/home/cache" MISE_DATA_DIR="$work/home/data/mise"
DS_JANET=$(command -v janet)
export DS_JANET DS_MISE="$work/mise" DS_TEST_LOG="$work/packages"
export DS_NVIM_SOURCE="$work/nvim" DS_TMUX_SOURCE="$work/tmux"
mkdir -p "$HOME" "$DS_NVIM_SOURCE" "$DS_TMUX_SOURCE"
cat >"$DS_MISE" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DS_TEST_LOG"
exit "${DS_TEST_EXIT:-0}"
SH
chmod 0755 "$DS_MISE"
prefix=$work/prefix
for version in one two; do
	candidate=$prefix/versions/$version
	mkdir -p "$candidate/src"
	cp "$root/ds" "$candidate/ds"
	cp -R "$root/src/scripts" "$root/src/mise" "$root/src/dotfiles" "$candidate/src/"
done
one=$prefix/versions/one/ds
two=$prefix/versions/two/ds
"$one" apply core --dry-run >"$work/plan"
[ ! -e "$prefix/current" ] || fail 'preview activated'
grep -q 'activate .*versions/one' "$work/plan" || fail 'activation absent from plan'
"$one" apply core >/dev/null
[ "$(readlink "$prefix/current")" = versions/one ] || fail 'apply did not activate'
: >"$DS_TEST_LOG"
if DS_TEST_EXIT=9 "$two" apply core >"$work/out" 2>"$work/err"; then fail 'failed packages activated'; fi
[ "$(readlink "$prefix/current")" = versions/one ] || fail 'package failure changed current'
[ ! -e "$prefix/.mutation-lock" ] || fail 'failure left lock'
(cd "$work" && "$one" activate two --prefix prefix --dry-run >/dev/null)
[ "$(readlink "$prefix/current")" = versions/one ] || fail 'activation preview wrote'
(cd "$work" && "$one" activate two --prefix prefix >/dev/null)
[ "$(readlink "$prefix/previous")" = versions/one ] || fail 'previous missing'
"$two" rollback >/dev/null
[ "$(readlink "$prefix/current")" = versions/one ] || fail 'rollback failed'
mkdir "$prefix/.mutation-lock"
if "$two" activate two >"$work/out" 2>"$work/err"; then fail 'busy activation succeeded'; fi
rmdir "$prefix/.mutation-lock"
[ "$(readlink "$prefix/current")" = versions/one ] || fail 'busy activation changed current'
for invalid in . .. ../one missing; do
	if "$one" activate "$invalid" >"$work/out" 2>"$work/err"; then fail "invalid version accepted: $invalid"; fi
done
rm "$XDG_CONFIG_HOME/ds/gitignore"
printf '%s\n' custom >"$XDG_CONFIG_HOME/ds/gitignore"
printf '%s\n' backup >"$XDG_CONFIG_HOME/ds/gitignore.ds-adopted"
: >"$DS_TEST_LOG"
"$two" adopt core --dry-run >"$work/plan"
grep -q 'backup exists' "$work/plan" || fail 'backup conflict missing from plan'
if "$two" adopt core >"$work/out" 2>"$work/err"; then fail 'backup overwritten'; fi
[ ! -s "$DS_TEST_LOG" ] || fail 'packages ran before conflict preflight'
[ "$(cat "$XDG_CONFIG_HOME/ds/gitignore.ds-adopted")" = backup ] || fail 'backup damaged'
rm "$XDG_CONFIG_HOME/ds/gitignore.ds-adopted"
"$one" adopt core >/dev/null
"$one" unapply core --dry-run >"$work/plan"
grep -q "restore $XDG_CONFIG_HOME/ds/gitignore.ds-adopted" "$work/plan" || fail 'restore absent from plan'
"$one" unapply core >/dev/null
[ "$(cat "$XDG_CONFIG_HOME/ds/gitignore")" = custom ] || fail 'original not restored'

mkdir -p "$work/dangling"
ln -s "$work/untouched" "$work/dangling/.zshrc"
: >"$DS_TEST_LOG"
if HOME="$work/dangling" XDG_CONFIG_HOME="$work/dangling/config" "$root/ds" apply core >"$work/out" 2>"$work/err"; then fail 'dangling rc link accepted'; fi
[ ! -e "$work/untouched" ] || fail 'apply followed dangling rc link'
[ ! -s "$DS_TEST_LOG" ] || fail 'packages ran before dangling-link conflict'

"$root/ds" status core --json >"$work/status.json"
check_json -e '.schema == 1 and (.components | length > 0) and (.files | length > 0)' "$work/status.json" >/dev/null
status=0
"$root/ds" status core --json --check >"$work/check.json" || status=$?
[ "$status" -eq 1 ] || fail 'unhealthy status exit contract'
status=0
"$root/ds" status core --invalid >"$work/out" 2>"$work/err" || status=$?
[ "$status" -eq 2 ] || fail 'usage exit contract'
mkdir -p "$MISE_DATA_DIR/installs/starship/1.22.0" "$XDG_CONFIG_HOME/ds"
printf '%s\n' starship >"$XDG_CONFIG_HOME/ds/components"
printf '%s\n' '#!/bin/sh' >"$MISE_DATA_DIR/installs/starship/1.22.0/starship"
chmod 0755 "$MISE_DATA_DIR/installs/starship/1.22.0/starship"
"$root/ds" status starship --json >"$work/status.json"
check_json -e '.components[0].state == "outdated" and .components[0].expected == "1.23.0"' "$work/status.json" >/dev/null
mkdir -p "$MISE_DATA_DIR/installs/starship/1.23.0/release/bin"
"$root/ds" status starship --json >"$work/status.json"
check_json -e '.components[0].state == "unavailable"' "$work/status.json" >/dev/null
cp "$MISE_DATA_DIR/installs/starship/1.22.0/starship" "$MISE_DATA_DIR/installs/starship/1.23.0/release/bin/starship"
"$root/ds" status starship --json --check >"$work/status.json"
check_json -e '.summary == "complete" and .components[0].state == "installed"' "$work/status.json" >/dev/null

"$root/ds" help adopt >"$work/help"
grep -q '^usage: ds adopt LAYER' "$work/help" || fail 'command-specific help missing'
"$root/ds" completion bash >"$work/completion.bash"
bash -c '. "$1"; COMP_WORDS=(ds add st); COMP_CWORD=2; _ds_complete; [[ "${COMPREPLY[*]}" == starship ]]' test "$work/completion.bash"
"$root/ds" completion zsh >"$work/completion.zsh"
zsh -n "$work/completion.zsh"

mkdir "$work/bin"
cat >"$work/bin/docker" <<'SH'
#!/bin/sh
case "$1" in info) exec sleep 10 ;; esac
SH
chmod 0755 "$work/bin/docker"
PATH="$work/bin:$PATH" "$root/ds" status remote --json >"$work/status.json"
check_json -e '.components[] | select(.component == "docker") | .state == "unavailable" and .probe == "timeout"' "$work/status.json" >/dev/null
printf '%s\n' '#!/bin/sh' 'exit 1' >"$work/bin/docker"
PATH="$work/bin:$PATH" "$root/ds" status remote --json >"$work/status.json"
check_json -e '.components[] | select(.component == "docker") | .probe == "unreachable"' "$work/status.json" >/dev/null

DS_TEST_HOME="$work" JANET_PATH="$root/src" "$DS_JANET" "$root/tests/decisions.janet"
printf '%s\n' 'decisions: ok'
