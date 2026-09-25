#!/bin/sh
set -eu

root=${1:-$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)}
root=$(CDPATH='' cd -P "$root" && pwd)
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
mkdir -p "$work/ignore-repo"
git -C "$work/ignore-repo" init -q
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
export DS_TEST_ROOT="$root" DS_TEST_CWD="$work/working dir" DS_TEST_IGNORE_REPO="$work/ignore-repo"
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
git -C "$DS_TEST_IGNORE_REPO" check-ignore -q .ai/probe || exit 68
git -C "$DS_TEST_IGNORE_REPO" check-ignore -q .swp || exit 69
git -C "$DS_TEST_IGNORE_REPO" check-ignore -q _sbt && exit 70
[[ $(<$XDG_CONFIG_HOME/application) == 'application settings' ]] || exit 19
[[ ${XDG_CONFIG_HOME:A} != ${DS_SHELL_CONFIG_HOME:A} ]] || exit 20
[[ ${XDG_CONFIG_HOME}/nvim -ef $DS_NVIM_SOURCE ]] || exit 21
[[ $HISTFILE == $DS_SHELL_STATE/zsh/history ]] || exit 22
[[ $ZDOTDIR == $DS_SHELL_STATE/zsh ]] || exit 40
[[ $commands[ds] == $DS_SHELL_STATE/bin/ds ]] || exit 23
[[ $commands[mise] == $DS_SHELL_STATE/bin/mise ]] || exit 24
[[ $aliases[vi] == nvim ]] || exit 25
[[ -z $functions[_zsh_autosuggest_start] ]] || exit 26
[[ $(fd) == trial-pinned-fd ]] || exit 27
[[ $aliases[gs] == 'git status' && $aliases[dcp] == 'docker pull' ]] || exit 28
[[ -o auto_cd && $galiases[...] == '../..' ]] || exit 29
[[ $commands[serve] == $DS_SHELL_STATE/bin/serve ]] || exit 35
serve --help >/dev/null || exit 36
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

# Apply stays inside the persistent shell.
mv "$HOME/.zshrc" "$work/daily-zshrc"
ln -s "$work/daily-zshrc" "$HOME/.zshrc"
mv "$HOME/.gitconfig" "$work/daily-gitconfig"
ln -s "$work/daily-gitconfig" "$HOME/.gitconfig"
cp "$work/daily-gitconfig" "$work/gitconfig-before"
mkdir -p "$HOME/.local/bin" "$XDG_CONFIG_HOME/nvim" "$work/tmux"
printf '%s\n' daily >"$XDG_CONFIG_HOME/nvim/user-config"
ln -s "$root/ds" "$HOME/.local/bin/ds"
printf '%s\n' '#!/bin/sh' 'exit 95' >"$HOME/.local/bin/serve"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$work/tmux/tm"
export DS_TMUX_SOURCE="$work/tmux" DS_TEST_LOG="$work/packages"
cat >"$DS_MISE" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DS_TEST_LOG"
SH
chmod +x "$DS_MISE" "$HOME/.local/bin/serve" "$work/tmux/tm"
cat >"$work/apply" <<'ZSH'
ds apply --dry-run >"$DS_SHELL_STATE/plan" || exit 41
grep -qx "scope: trial configuration" "$DS_SHELL_STATE/plan" || exit 60
grep -qx "layer: core" "$DS_SHELL_STATE/plan" || exit 61
if grep -q blocked "$DS_SHELL_STATE/plan"; then exit 42; fi
ds apply core || exit 43
ds apply core || exit 44
[[ $HISTFILE == $ZDOTDIR/history ]] || exit 45
[[ $commands[serve] == $DS_SHELL_STATE/bin/serve ]] || exit 46
[[ $(git config core.excludesFile) == $XDG_CONFIG_HOME/ds/gitignore ]] || exit 47
zsh -d -ic '[[ $HISTFILE == $ZDOTDIR/history && $aliases[gst] == "git status" ]]' || exit 48
print -r -- 'export DS_TEST_LOCAL=kept' >>"$ZDOTDIR/.zshrc"
print -s -- ds-persistent-history
fc -AI
ds apply remote --skip docker || exit 50
[[ $MISE_ENV == core,remote ]] || exit 51
[[ -L $XDG_CONFIG_HOME/ds/yazi ]] || exit 71
[[ $aliases[r] == yazi_cd ]] || exit 75
exit 0
ZSH
"$HOME/.local/bin/ds" shell <"$work/apply" >"$work/out" 2>"$work/err" || {
	cat "$work/out" "$work/err"
	exit 1
}
[ -s "$DS_TEST_LOG" ]
mkdir -p "$work/bin"
cat >"$work/bin/yazi" <<'SH'
#!/bin/sh
for argument do
	case $argument in
	--cwd-file=*) printf '%s' "$DS_TEST_TARGET" >"${argument#--cwd-file=}" ;;
	esac
done
SH
chmod +x "$work/bin/yazi"
export DS_TEST_TARGET="$work"
PATH="$work/bin:$PATH" "$HOME/.local/bin/ds" shell >"$work/out" 2>"$work/err" <<'ZSH' || {
[[ $DS_TEST_LOCAL == kept ]] || exit 52
[[ $MISE_ENV == core,remote ]] || exit 53
[[ $YAZI_CONFIG_HOME == $XDG_CONFIG_HOME/ds/yazi ]] || exit 72
[[ $aliases[r] == yazi_cd ]] || exit 73
r
[[ $PWD == $DS_TEST_TARGET ]] || exit 74
grep -qx ds-persistent-history "$HISTFILE" || exit 54
[[ $(git config trial.setting) == kept ]] || exit 55
ds status --json >"$DS_SHELL_STATE/status" || exit 62
grep -q '"target":"core,remote"' "$DS_SHELL_STATE/status" || exit 63
[[ $MISE_ENV == core,remote ]] || exit 65
ds remove remote || exit 56
ds remove core || exit 66
[[ -f $ZDOTDIR/.zshrc ]] || exit 57
[[ -z $(grep 'ds managed' "$ZDOTDIR/.zshrc") ]] || exit 58
ds --help >/dev/null || exit 59
exit 0
ZSH
	cat "$work/out" "$work/err"
	exit 1
}
[ "$(readlink "$HOME/.zshrc")" = "$work/daily-zshrc" ]
[ "$(cat "$HOME/.zshrc")" = 'exit 91' ]
[ "$(readlink "$HOME/.gitconfig")" = "$work/daily-gitconfig" ]
cmp "$HOME/.gitconfig" "$work/gitconfig-before"
[ "$(readlink "$HOME/.local/bin/ds")" = "$root/ds" ]
[ "$(tail -n 1 "$HOME/.local/bin/serve")" = 'exit 95' ]
[ "$(cat "$XDG_CONFIG_HOME/nvim/user-config")" = daily ]
[ ! -e "$XDG_CONFIG_HOME/ds" ]
printf '%s\n' 'trial shell: ok'
