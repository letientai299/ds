#!/bin/sh

set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-ux.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM
. "$root/tests/optional-fixture.sh"
optional_fixture "$root" "$work/source"
root=$work/source

fail() {
	printf '%s\n' "ux: $*" >&2
	exit 1
}

export HOME="$work/home" XDG_CONFIG_HOME="$work/home/config"
export XDG_DATA_HOME="$work/home/data" XDG_STATE_HOME="$work/home/state"
export XDG_CACHE_HOME="$work/home/cache" DS_ROOT="$root"
DS_JANET=$(command -v janet)
export DS_JANET DS_MISE="$work/mise"
export DS_NVIM_SOURCE="$work/nvim" DS_TMUX_SOURCE="$work/tmux"
mkdir -p "$XDG_CONFIG_HOME/ds" "$DS_NVIM_SOURCE" "$DS_TMUX_SOURCE" "$work/bin"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$DS_MISE"
chmod 0755 "$DS_MISE"
printf '%s\n' example >"$XDG_CONFIG_HOME/ds/components"
"$root/ds" apply core >/dev/null
cp "$HOME/.zshrc" "$work/zshrc"

for target in core example; do
	"$root/ds" remove "$target" --dry-run >"$work/preview"
	grep -qx "would remove $target" "$work/preview" || fail 'missing remove preview'
	[ -L "$HOME/.local/bin/ds" ] || fail 'preview removed launcher'
	[ "$(cat "$XDG_CONFIG_HOME/ds/components")" = example ] || fail 'preview removed selection'
	cmp "$HOME/.zshrc" "$work/zshrc" || fail 'preview changed shell configuration'
done

reject() {
	if "$root/ds" "$@" >"$work/out" 2>"$work/err"; then
		fail "unexpected success: $*"
	fi
	grep -q '^ds: ' "$work/err" || fail 'missing argument diagnostic'
}
reject remove core --dryrun
reject remove example extra
reject status core extra
reject diff core extra
reject doctor core extra
reject shell extra
reject shell-init extra
reject docker-rootful --approve-rootful --grant-docker-group extra
[ -L "$HOME/.local/bin/ds" ] || fail 'invalid arguments removed launcher'
[ "$(cat "$XDG_CONFIG_HOME/ds/components")" = example ] || fail 'invalid arguments removed selection'
for command in apply remove add status diff doctor push; do
	"$root/ds" "$command" --help >"$work/help"
	grep -q '^usage:' "$work/help" || fail "missing help: $command"
done
DS_ROOT=/stale/version "$HOME/.local/bin/ds" help >"$work/link-help"
grep -q '^usage:' "$work/link-help" || fail 'installed symlink failed'

if command -v zsh >/dev/null 2>&1; then
	cat >"$XDG_CONFIG_HOME/ds/local.zsh" <<'ZSH'
print refreshed >>"$HOME/refresh.log"
ZSH
	DS_ROOT=/stale/version zsh -dfc '
        source "$1"
        : >"$HOME/refresh.log"
        [[ "$MISE_ENV" == core,example ]] || exit 1
        ds remove example --dry-run >/dev/null
        ds remove --help >/dev/null
        [[ ! -s "$HOME/refresh.log" ]] || exit 1
        [[ "$MISE_ENV" == core,example ]] || exit 1
        ds remove example >/dev/null
        [[ -s "$HOME/refresh.log" ]] || exit 1
        [[ "$MISE_ENV" == core ]] || exit 1
    ' ds-ux "$root/src/dotfiles/shell.zsh" || fail 'shell selection refresh failed'
fi

cat >"$work/bin/docker" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DS_DOCKER_LOG"
case "$1" in info) printf '%s\n' '[]' ;; esac
SH
chmod 0755 "$work/bin/docker"
PATH="$work/bin:$PATH" DS_DOCKER_LOG="$work/docker.log" \
	"$root/ds" doctor remote >"$work/doctor"
[ "$(grep -c '^info ' "$work/docker.log")" -eq 1 ] || fail 'Docker info repeated'
grep -q 'Docker daemon, Compose, and Buildx are ready' "$work/doctor" || fail 'Docker readiness regressed'
: >"$work/docker.log"
PATH="$work/bin:$PATH" DS_DOCKER_LOG="$work/docker.log" \
	"$root/ds" status remote --verbose >"$work/status-docker"
[ "$(grep -c '^info ' "$work/docker.log")" -eq 1 ] || fail 'verbose status repeated Docker info'
grep -q 'Docker daemon, Compose, and Buildx are ready' "$work/status-docker" || fail 'verbose status omitted diagnostics'

printf '%s\n' '#!/bin/sh' 'exit 0' >"$DS_TMUX_SOURCE/tm"
chmod 0755 "$DS_TMUX_SOURCE/tm"
for flag in --force --adopt; do
	: >"$work/docker.log"
	PATH="$work/bin:$PATH" DS_DOCKER_LOG="$work/docker.log" \
		"$root/ds" apply remote "$flag" >"$work/takeover"
	grep -q '^docker: ' "$work/takeover" || fail 'takeover omitted Docker convergence'
	[ "$(grep -c '^info ' "$work/docker.log")" -eq 1 ] || fail 'takeover repeated Docker info'
done
rm "$work/bin/docker"
mkdir "$work/bin/docker"
PATH="$work/bin:/usr/bin:/bin" "$root/ds" doctor remote >"$work/directory-docker"

"$root/ds" -h >"$work/help"
for command in shell apply status remove push; do
	grep -q "^  $command " "$work/help" || fail "primary command absent: $command"
done
for command in stage activate rollback shell-init completion docker-rootful add diff doctor docker; do
	if grep -q "^  $command " "$work/help"; then fail "advanced command exposed: $command"; fi
done
"$root/ds" help --all >"$work/all-help"
grep -q '^  rollback ' "$work/all-help" || fail 'advanced help missing recovery'
"$root/ds" apply --help >"$work/help"
grep -qx 'example: ds apply --dry-run' "$work/help" || fail 'apply example changed commands'
for command in apply push; do
	"$root/ds" help "$command" >"$work/help"
	grep -q -- '--force' "$work/help" || fail 'force missing from help'
	if grep -q -- '--adopt' "$work/help"; then fail 'help advertises old flag'; fi
done
for shell in bash zsh; do
	"$root/ds" completion "$shell" >"$work/completion"
	grep -q -- '--force' "$work/completion" || fail 'force missing from completion'
	if grep -q -- '--adopt' "$work/completion"; then fail 'completion advertises old flag'; fi
done
"$root/ds" completion --help >"$work/help"
if grep -q '^targets:' "$work/help"; then fail 'integration help includes targets'; fi

reject remove
reject remove --dry-run
reject remove core extra
reject apply example --adopt
reject apply --force example
reject apply example --skip docker
reject apply --skip
reject apply --skip fzf
reject remove core --adopt
reject status --unknown

"$root/ds" apply --dry-run --skip docker >"$work/default-plan"
grep -qx 'layer: core,remote' "$work/default-plan" || fail 'apply ignored saved layer'
grep -qx 'would apply core,remote:' "$work/default-plan" || fail 'apply default target missing'
"$root/ds" apply --dry-run core >"$work/explicit-plan"
grep -qx 'layer: core' "$work/explicit-plan" || fail 'explicit layer ignored'
"$root/ds" status --json >"$work/default-json"
"$root/ds" status --json >"$work/explicit-json"
cmp "$work/default-json" "$work/explicit-json" || fail 'status ignored saved layer'
"$root/ds" status core >"$work/brief"
"$root/ds" status --verbose core >"$work/verbose"
if grep -Eq '^  (installed|present) ' "$work/brief"; then fail 'brief status includes healthy entries'; fi
grep -q '^  present ' "$work/verbose" || fail 'verbose status omitted healthy files'
grep -qx 'scope: normal configuration' "$work/brief" || fail 'normal scope missing'
"$root/ds" doctor core >"$work/legacy-doctor"
if grep -q '^scope:' "$work/legacy-doctor"; then fail 'legacy doctor output changed'; fi
grep -q '^  present ' "$work/legacy-doctor" || fail 'legacy doctor hid healthy files'

printf '%s\n' invalid >"$XDG_CONFIG_HOME/ds/layer"
reject apply --dry-run
reject status --json
grep -q 'invalid saved layer' "$work/err" || fail 'invalid selection silently defaulted'
"$root/ds" apply core --dry-run >/dev/null
"$root/ds" status core --json >/dev/null
rm "$XDG_CONFIG_HOME/ds/layer"
"$root/ds" apply --dry-run >"$work/default-plan"
grep -qx 'would apply core:' "$work/default-plan" || fail 'initial apply did not default to core'
[ ! -e "$XDG_CONFIG_HOME/ds/layer" ] || fail 'default preview wrote selection'

rm "$XDG_CONFIG_HOME/ds/gitignore"
printf '%s\n' original >"$XDG_CONFIG_HOME/ds/gitignore"
if "$root/ds" apply core >"$work/out" 2>"$work/err"; then fail 'apply accepted conflict'; fi
grep -q 'ds apply core --force --dry-run' "$work/err" || fail 'conflict omitted preview command'
"$root/ds" status core >"$work/conflict"
grep -qx 'preview: ds apply core --force --dry-run' "$work/conflict" || fail 'status omitted conflict action'
"$root/ds" apply --adopt core --dry-run >"$work/adopt-plan"
grep -q '^  backup ' "$work/adopt-plan" || fail 'adoption preview omitted backup'
[ ! -e "$XDG_CONFIG_HOME/ds/gitignore.ds-adopted" ] || fail 'adoption preview wrote backup'
"$root/ds" apply core --adopt >/dev/null
[ "$(cat "$XDG_CONFIG_HOME/ds/gitignore.ds-adopted")" = original ] || fail 'adoption lost original'
"$root/ds" remove core --dry-run >"$work/remove-plan"
grep -q '^  restore ' "$work/remove-plan" || fail 'removal preview omitted restoration'
"$root/ds" remove core >/dev/null
[ "$(cat "$XDG_CONFIG_HOME/ds/gitignore")" = original ] || fail 'removal did not restore original'
"$root/ds" apply core --force --dry-run >"$work/force-plan"
grep -q '^  backup ' "$work/force-plan" || fail 'force preview omitted backup'
[ ! -e "$XDG_CONFIG_HOME/ds/gitignore.ds-adopted" ] || fail 'force preview wrote backup'
"$root/ds" apply --force --adopt core --dry-run >"$work/alias-plan"
cmp "$work/force-plan" "$work/alias-plan" || fail 'aliases changed force plan'
"$root/ds" apply --force core >/dev/null
[ -L "$XDG_CONFIG_HOME/ds/gitignore" ] || fail 'force did not replace conflict'
[ "$(cat "$XDG_CONFIG_HOME/ds/gitignore.ds-adopted")" = original ] || fail 'force lost original'
"$root/ds" remove core >/dev/null
[ "$(cat "$XDG_CONFIG_HOME/ds/gitignore")" = original ] || fail 'force backup not restored'
"$root/ds" apply core --force >/dev/null
[ "$(cat "$XDG_CONFIG_HOME/ds/gitignore.ds-adopted")" = original ] || fail 'force lost original'
"$root/ds" apply example >/dev/null
[ "$(cat "$XDG_CONFIG_HOME/ds/components")" = example ] || fail 'apply did not select component'
"$root/ds" remove example >/dev/null
[ ! -e "$XDG_CONFIG_HOME/ds/components" ] || fail 'remove did not clear selection'

"$root/ds" completion bash >"$work/completion.bash"
bash -c '
    source "$1"
    COMP_WORDS=(ds ""); COMP_CWORD=1; _ds_complete
    [[ "${COMPREPLY[*]}" == "shell apply status remove push help --help" ]] || exit 1
    COMP_WORDS=(ds roll); _ds_complete
    [[ "${COMPREPLY[*]}" == rollback ]] || exit 2
    COMP_WORDS=(ds apply exam); COMP_CWORD=2; _ds_complete
    [[ "${COMPREPLY[*]}" == example ]] || exit 3
    COMP_WORDS=(ds apply --skip ""); COMP_CWORD=3; _ds_complete
    [[ "${COMPREPLY[*]}" == docker ]] || exit 4
    COMP_WORDS=(ds help --a); COMP_CWORD=2; _ds_complete
    [[ "${COMPREPLY[*]}" == --all ]] || exit 5
    COMP_WORDS=(ds shell --docker -- printf --h); COMP_CWORD=5; _ds_complete
    [[ ${#COMPREPLY[@]} == 0 ]] || exit 6
' test "$work/completion.bash" || fail 'completion choices failed'
"$root/ds" completion zsh >"$work/completion.zsh"
zsh -fc '
    compdef() { :; }
    compadd() { shift; [[ $1 == -- ]] && shift; print -rl -- "$@"; }
    source "$1"
    words=(ds status --v); CURRENT=3; _ds_complete
' test "$work/completion.zsh" >"$work/zsh-choices"
grep -qx -- --verbose "$work/zsh-choices" || fail 'Zsh completion omitted verbose'

printf '%s\n' 'ux: ok'
