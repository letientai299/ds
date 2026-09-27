#!/bin/sh

set -eu

mode=$1
manifest_sha=$2
installed=$(/snapshot/bootstrap.sh --source /snapshot \
	--prefix "$HOME/.local/share/ds" --manifest-sha256 "$manifest_sha")

check_shell() {
	layer=$1
	# Warm caches before checking repeat startup.
	zsh -f -c 'source "$HOME/.config/ds/shell.zsh"'
	find "$HOME" -print | sort >/tmp/ds-before-paths
	find "$HOME" -type f -exec sha256sum {} + | sort >/tmp/ds-before-hashes
	zsh -ef -c 'source "$HOME/.config/ds/shell.zsh"; test -f "$HOME/.config/nvim/init.lua"'
	find "$HOME" -print | sort >/tmp/ds-after-paths
	find "$HOME" -type f -exec sha256sum {} + | sort >/tmp/ds-after-hashes
	for kind in paths hashes; do
		if [ "$(sha256sum <"/tmp/ds-before-$kind")" != "$(sha256sum <"/tmp/ds-after-$kind")" ]; then
			printf 'shell startup changed %s\n' "$kind" >&2
			cat "/tmp/ds-before-$kind" "/tmp/ds-after-$kind" >&2
			exit 1
		fi
	done
	printf '%s\n' "$layer shell: ok"
}

check_core() {
	zsh -ef -c '
		source "$HOME/.config/ds/shell.zsh"
		for tool in mise fd fzf rg tree-sitter nvim zoxide jq xh; do
			"$tool" --version >/dev/null
		done
		ds help >/dev/null
		nvim --headless --clean +qa
	'
}

check_remote() {
	"$installed/ds" status remote --verbose >/tmp/ds-status
	grep -q '^  missing docker$' /tmp/ds-status
	grep -q '^  installed tmux$' /tmp/ds-status
	grep -q '^  installed zoxide ' /tmp/ds-status
	grep -q '^  installed yazi ' /tmp/ds-status
	command -v file >/dev/null
	zsh -ef -c '
		source "$HOME/.config/ds/shell.zsh"
		(( $+functions[yazi_cd] ))
		[[ $YAZI_CONFIG_HOME == $XDG_CONFIG_HOME/ds/yazi ]]
		[[ $aliases[r] == yazi_cd ]]
		yazi --version >/dev/null
		tm new-session -d -s ds-e2e sleep 30
		[[ "$(tm show-options -sv set-clipboard)" = on ]]
		tm show-options -sv terminal-features | grep -q clipboard
		tm has-session -t ds-e2e
		tm kill-server
	'
}

if [ "$mode" != remote ]; then
	started=$(date +%s)
	"$installed/ds" apply core
	"$installed/ds" status core --check
	"$installed/ds" apply core
	"$installed/ds" status core --check
	check_shell core
	check_core
	printf 'core: ok in %ss\n' "$(($(date +%s) - started))"
fi
if [ "$mode" = remote ] || [ "$mode" = core-remote ]; then
	started=$(date +%s)
	"$installed/ds" apply remote
	check_shell remote
	[ "$mode" != remote ] || check_core
	check_remote
	printf 'remote: ok in %ss\n' "$(($(date +%s) - started))"
fi
