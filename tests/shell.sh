#!/bin/sh
set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-shell.XXXXXX")
work=$(CDPATH='' cd -P "$work" && pwd)
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM
DS_JANET=$(command -v janet)
export DS_JANET
export HOME="$work/home" XDG_CONFIG_HOME="$work/home/config"
export XDG_STATE_HOME="$work/home/state" XDG_CACHE_HOME="$work/home/cache"
export XDG_DATA_HOME="$work/home/data" MISE_DATA_DIR="$work/tools"
export DS_NVIM_SOURCE="$work/nvim" DS_MISE="$work/mise"
export DS_ROOT=/stale/root ZDOTDIR="$work/old-zdotdir"
unset DS_SHELL_ROOT DS_SHELL_CONFIG_HOME DS_SHELL_GIT_GLOBAL DS_SHELL_STATE GIT_CONFIG_GLOBAL
mkdir -p "$HOME" "$DS_NVIM_SOURCE" "$XDG_CONFIG_HOME/git" "$work/working dir" "$ZDOTDIR"
printf '%s\n' 'exit 91' >"$HOME/.zshrc"
printf '%s\n' 'exit 92' >"$ZDOTDIR/.zshrc"
printf '%s\n' '[user]' 'name = Daily User' >"$HOME/.gitconfig"
printf '%s\n' '[user]' 'email = daily@example.invalid' >"$XDG_CONFIG_HOME/git/config"
printf '%s\n' 'application settings' >"$XDG_CONFIG_HOME/application"
printf '%s\n' '#!/bin/sh' 'exit 93' >"$DS_MISE"
chmod +x "$DS_MISE"
fd_version=$(JANET_PATH="$root/src" "$DS_JANET" -e '(import scripts/generated/layers :as g) (print (get-in g/catalog [:components :fd :version]))')
mkdir -p "$MISE_DATA_DIR/installs/fd/$fd_version/bin"
printf '%s\n' '#!/bin/sh' 'echo trial-pinned-fd' >"$MISE_DATA_DIR/installs/fd/$fd_version/bin/fd"
chmod +x "$MISE_DATA_DIR/installs/fd/$fd_version/bin/fd"
export DS_TEST_ROOT="$root" DS_TEST_CWD="$work/working dir"
cat >"$work/input" <<'ZSH'
[[ $$ == $DS_TEST_PID ]] || exit 10
[[ $PWD == $DS_TEST_CWD ]] || exit 11
[[ $HOME == $DS_TEST_HOME ]] || exit 12
[[ $DS_DS == $DS_TEST_ROOT/ds ]] || exit 13
[[ $MISE_DATA_DIR == $DS_TEST_TOOLS ]] || exit 14
[[ $(git config user.name) == 'Daily User' ]] || exit 15
[[ $(git config user.email) == daily@example.invalid ]] || exit 16
[[ $(git config push.autoSetupRemote) == true ]] || exit 17
[[ $(git config core.excludesFile) == $XDG_CONFIG_HOME/ds/gitignore ]] || exit 18
[[ $(<$XDG_CONFIG_HOME/application) == 'application settings' ]] || exit 19
[[ ${XDG_CONFIG_HOME:A} != ${DS_SHELL_CONFIG_HOME:A} ]] || exit 20
[[ ${XDG_CONFIG_HOME}/nvim -ef $DS_NVIM_SOURCE ]] || exit 21
[[ $HISTFILE == $DS_SHELL_STATE/zsh/history ]] || exit 22
[[ $commands[ds] == $DS_SHELL_STATE/bin/ds ]] || exit 23
[[ $commands[mise] == $DS_SHELL_STATE/bin/mise ]] || exit 24
[[ $aliases[vi] == nvim ]] || exit 25
[[ -z $functions[_zsh_autosuggest_start] ]] || exit 26
[[ $(fd) == trial-pinned-fd ]] || exit 27
[[ $aliases[gs] == 'git status' && $aliases[dcp] == 'docker pull' ]] || exit 28
[[ -o auto_cd && $galiases[...] == '../..' ]] || exit 29
print -r -- trial-ready
exit 0
ZSH
export DS_TEST_HOME="$HOME" DS_TEST_TOOLS="$MISE_DATA_DIR"
(
	cd "$DS_TEST_CWD"
	sh -c 'export DS_TEST_PID=$$; exec "$1"' sh "$root/ds" <"$work/input" >"$work/out" 2>"$work/err"
) || {
	printf 'trial failed: %s\n' "$?"
	cat "$work/out" "$work/err"
	exit 1
}
grep -qx trial-ready "$work/out"
# Reentry preserves PID and Git includes.
{
	printf '%s\n' "exec \"\$DS_DS\" shell"
	cat "$work/input"
} >"$work/reentry"
(
	cd "$DS_TEST_CWD"
	sh -c 'export DS_TEST_PID=$$; exec "$1" shell' sh "$root/ds" <"$work/reentry" >"$work/out" 2>"$work/err"
) || {
	printf 'trial reentry failed: %s\n' "$?"
	cat "$work/out" "$work/err"
	exit 1
}
grep -qx trial-ready "$work/out"
[ "$(cat "$HOME/.zshrc")" = 'exit 91' ]
[ "$(cat "$ZDOTDIR/.zshrc")" = 'exit 92' ]
[ ! -e "$HOME/.local/bin/ds" ]
printf '%s\n' 'exit 37' | "$root/ds" shell >"$work/out" 2>"$work/err" && code=0 || code=$?
[ "$code" -eq 37 ]
printf '%s\n' '[user]' 'name = Custom User' >"$work/custom-git"
GIT_CONFIG_GLOBAL="$work/custom-git" "$root/ds" shell >"$work/out" 2>"$work/err" <<'ZSH'
[[ $(git config user.name) == 'Custom User' ]] || exit 30
[[ -z $(git config user.email) ]] || exit 31
git config --global trial.setting kept || exit 32
exec "$DS_DS"
[[ $(git config trial.setting) == kept ]] || exit 33
[[ $(git config user.name) == 'Custom User' ]] || exit 34
exit 0
ZSH
printf '%s\n' 'trial shell: ok'
