#!/bin/sh
set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-plugins.XXXXXX")
work=$(CDPATH='' cd -P "$work" && pwd)
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM
mkdir -p "$work/bin"
cat >"$work/bin/fzf" <<'SH'
#!/bin/sh
if [ "$1" = --zsh ]; then
  echo 'function fzf-completion() { zle .expand-or-complete; }'
  echo 'zle -N fzf-completion'
  echo 'bindkey "^I" fzf-completion'
else
  echo 0.74.2
fi
SH
chmod +x "$work/bin/fzf"

for mode in fresh existing; do
	mkdir -p "$work/$mode/.local/state/zsh" "$work/$mode/.local/share/mise/installs/fzf/latest"
	ln -s "$work/bin/fzf" "$work/$mode/.local/share/mise/installs/fzf/latest/fzf"
	env -i HOME="$work/$mode" ZDOTDIR="$work/$mode" TERM=xterm-256color \
		PATH="$work/bin:$PATH" DS_JANET="$(command -v janet)" \
		DS_TEST_SHELL="${1:-$root/src/dotfiles/shell.zsh}" DS_TEST_MODE="$mode" \
		zsh -df "$root/tests/plugins.zsh"
done
