#!/bin/sh

set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-ux.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM

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
printf '%s\n' starship >"$XDG_CONFIG_HOME/ds/components"
"$root/ds" apply core >/dev/null
cp "$HOME/.zshrc" "$work/zshrc"

for target in core starship; do
	"$root/ds" unapply "$target" --dry-run >"$work/preview"
	grep -qx "would unapply $target" "$work/preview" || fail 'missing unapply preview'
	[ -L "$HOME/.local/bin/ds" ] || fail 'preview removed launcher'
	[ "$(cat "$XDG_CONFIG_HOME/ds/components")" = starship ] || fail 'preview removed selection'
	cmp "$HOME/.zshrc" "$work/zshrc" || fail 'preview changed shell configuration'
done

reject() {
	if "$root/ds" "$@" >"$work/out" 2>"$work/err"; then
		fail "unexpected success: $*"
	fi
	grep -q '^ds: ' "$work/err" || fail 'missing argument diagnostic'
}
reject unapply core --dryrun
reject unapply starship extra
reject status core extra
reject diff core extra
reject doctor core extra
reject shell extra
reject shell-init extra
reject docker-rootful --approve-rootful --grant-docker-group extra
[ -L "$HOME/.local/bin/ds" ] || fail 'invalid arguments removed launcher'
[ "$(cat "$XDG_CONFIG_HOME/ds/components")" = starship ] || fail 'invalid arguments removed selection'
for command in apply unapply adopt force add status diff doctor push; do
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
        [[ "$MISE_ENV" == starship ]] || exit 1
        ds unapply starship --dry-run >/dev/null
        ds unapply --help >/dev/null
        [[ ! -s "$HOME/refresh.log" ]] || exit 1
        [[ "$MISE_ENV" == starship ]] || exit 1
        ds unapply starship >/dev/null
        [[ -s "$HOME/refresh.log" ]] || exit 1
        [[ -z "$MISE_ENV" ]] || exit 1
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

printf '%s\n' '#!/bin/sh' 'exit 0' >"$DS_TMUX_SOURCE/tm"
chmod 0755 "$DS_TMUX_SOURCE/tm"
for command in adopt force; do
	: >"$work/docker.log"
	PATH="$work/bin:$PATH" DS_DOCKER_LOG="$work/docker.log" \
		"$root/ds" "$command" remote >"$work/takeover"
	grep -q '^docker: ' "$work/takeover" || fail 'takeover omitted Docker convergence'
	[ "$(grep -c '^info ' "$work/docker.log")" -eq 1 ] || fail 'takeover repeated Docker info'
done
rm "$work/bin/docker"
mkdir "$work/bin/docker"
PATH="$work/bin:/usr/bin:/bin" "$root/ds" doctor remote >"$work/directory-docker"

printf '%s\n' 'ux: ok'
