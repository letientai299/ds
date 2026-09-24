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
cat >"$work/bin/zoxide" <<'SH'
#!/bin/sh
if [ "$1" = init ]; then
  echo 'function zoxide-ready() { :; }'
fi
SH
chmod +x "$work/bin/zoxide"
cat >"$work/bin/mise" <<'SH'
#!/bin/sh
if [ "$1" = activate ] && [ "$2" = zsh ]; then
  echo 'export DS_TEST_MISE_READY=1'
fi
SH
chmod +x "$work/bin/mise"

for mode in fresh existing; do
	mkdir -p "$work/$mode/.local/state/zsh" "$work/$mode/.local/share/mise/installs/fzf/latest" \
		"$work/$mode/.local/share/mise/installs/zoxide/latest"
	ln -s "$work/bin/fzf" "$work/$mode/.local/share/mise/installs/fzf/latest/fzf"
	ln -s "$work/bin/zoxide" "$work/$mode/.local/share/mise/installs/zoxide/latest/zoxide"
	env -i HOME="$work/$mode" ZDOTDIR="$work/$mode" TERM=xterm-256color \
		PATH="$work/bin:$PATH" DS_JANET="$(command -v janet)" DS_MISE_ACTIVATE=1 \
		DS_TEST_SHELL="${1:-$root/src/dotfiles/shell.zsh}" DS_TEST_MODE="$mode" \
		zsh -df "$root/tests/plugins.zsh"
done
