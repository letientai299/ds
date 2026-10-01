#!/bin/sh

set -eu

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-managed.XXXXXX")
# shellcheck source=tests/isolate.sh
. "$(dirname -- "$0")/isolate.sh"
isolate_home "$work/isolated-home"
trap 'rm -rf "$work"' EXIT HUP INT TERM

DS_TEST_HOME=$work/home DS_ROOT=$root DS_MISE=$(command -v mise) JANET_PATH=$root/src janet "$root/tests/managed.janet"
(
	cd "$work"
	HOME="$work/home/migration" MISE_CONFIG_DIR="$work/home/migration/config/mise" \
		mise config ls --json >"$work/config-list"
	HOME="$work/home/migration" MISE_CONFIG_DIR="$work/home/migration/config/mise" \
		mise set -g DS_TEST_SETTING=local
)
grep -q 'config.toml' "$work/config-list"
grep -q 'npm:git-open' "$work/config-list"
grep -q 'neovim' "$work/config-list"
[ ! -L "$work/home/migration/config/mise/config.toml" ]
grep -q 'DS_TEST_SETTING = "local"' "$work/home/migration/config/mise/config.toml"
if grep -q DS_TEST_SETTING "$root/src/mise/mise.toml"; then
	exit 1
fi

(
	cd "$work"
	export HOME="$work/home/migration" XDG_CONFIG_HOME="$work/home/migration/config"
	export DS_SHELL_ROOT="$root" MISE_GLOBAL_CONFIG_FILE="$root/src/mise/mise.toml"
	zsh -fc 'source "$DS_SHELL_ROOT/src/dotfiles/shell.zsh"
[[ -z ${MISE_GLOBAL_CONFIG_FILE+x} ]] || exit 1
mise config ls --json' >"$work/shell-config-list"
)
grep -q 'config.toml' "$work/shell-config-list"
grep -q 'neovim' "$work/shell-config-list"

mkdir -p "$work/home/migration/.config/mise"
printf '%s\n' '[env]' 'DS_TEST_LEGACY = "leaked"' >"$work/home/migration/.config/mise/config.toml"
case_index=0
for layout in mise.toml .mise.toml .config/mise.toml .config/mise/config.toml; do
	case_index=$((case_index + 1))
	project="$work/home/migration/projects/case-$case_index"
	mkdir -p "$project/$(dirname "$layout")" "$project/nested"
	printf '%s\n' '[tasks.probe]' 'run = "echo project-found"' >"$project/$layout"
	(
		cd "$project/nested"
		env HOME="$work/home/migration" XDG_CONFIG_HOME="$work/home/migration/config" \
			DS_SHELL_ROOT="$root" MISE_OVERRIDE_CONFIG_FILENAMES=mise.toml \
			MISE_CEILING_PATHS="$work/unrelated" \
			DS_TEST_CEILINGS="$work/home/migration:$work/unrelated" \
			zsh -ef >"$work/project-config-list" <<'ZSH'
source "$DS_SHELL_ROOT/src/dotfiles/shell.zsh"
source "$DS_SHELL_ROOT/src/dotfiles/shell.zsh"
[[ -z ${MISE_OVERRIDE_CONFIG_FILENAMES+x} ]] || exit 1
[[ $MISE_CEILING_PATHS == "$DS_TEST_CEILINGS" ]] || exit 2
export MISE_TRUSTED_CONFIG_PATHS="$HOME"
mise tasks ls --json
mise config ls --json
mise set -g DS_TEST_SHELL_SETTING=local
ZSH
	)
	grep -q '"name": "probe"' "$work/project-config-list"
	grep -q config.toml "$work/project-config-list"
	grep -q neovim "$work/project-config-list"
	if grep -Fq "$work/home/migration/.config/mise/config.toml" "$work/project-config-list"; then
		exit 1
	fi
done
grep -q 'DS_TEST_SHELL_SETTING = "local"' "$work/home/migration/config/mise/config.toml"
if grep -q DS_TEST_SHELL_SETTING "$root/src/mise/mise.toml"; then
	exit 1
fi

mkdir -p "$work/shfmt/bin"
cp "$(command -v shfmt)" "$work/shfmt/bin/shfmt"
shfmt_version=$(shfmt --version)
cksum "$root"/src/mise/*.toml >"$work/profiles-before"
env HOME="$work/home/migration" XDG_CONFIG_HOME="$work/home/migration/config" \
	DS_SHELL_ROOT="$root" DS_TEST_TOOL="$work/shfmt" DS_TEST_VERSION="${shfmt_version#v}" \
	MISE_CEILING_PATHS="$(dirname "$root")" \
	zsh -ef <<'ZSH'
source "$DS_SHELL_ROOT/src/dotfiles/shell.zsh"
export MISE_TRUSTED_CONFIG_PATHS="$DS_SHELL_ROOT"
mise link "shfmt@$DS_TEST_VERSION" "$DS_TEST_TOOL"
cd "$DS_SHELL_ROOT"
mise use -g "shfmt@$DS_TEST_VERSION"
grep -q shfmt "$MISE_CONFIG_DIR/config.toml"
cd "$HOME"
shfmt --version
ZSH
cksum "$root"/src/mise/*.toml >"$work/profiles-after"
cmp "$work/profiles-before" "$work/profiles-after"
