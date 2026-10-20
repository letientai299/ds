#!/usr/bin/env zsh
setopt err_exit no_unset pipe_fail
root=${0:A:h:h}
work=$(mktemp -d)
trap 'command rm -rf -- "$work"' EXIT

fail() {
  print -ru2 -- "$1"
  exit 1
}

for tool in bat eza fd rg xh ouch sd yazi ya delta tree-sitter codex; do
  install=$tool
  [[ $tool != rg ]] || install=ripgrep
  [[ $tool != ouch ]] || install=aqua-ouch-org-ouch
  [[ $tool != ya ]] || install=yazi
  [[ $tool != delta ]] || install=aqua-dandavison-delta
  directory="$work/mise/installs/$install/latest/share/zsh/site-functions"
  mkdir -p "$directory"
  printf '#compdef %s\n_arguments "--help[Show help]"\n' "$tool" > "$directory/_$tool"
done

for mode in fresh initialized; do
  ROOT="$root" WORK="$work" MODE="$mode" zsh -dfi -c '
setopt err_exit
export XDG_DATA_HOME="$WORK/data" XDG_CACHE_HOME="$WORK/cache"
export MISE_DATA_DIR="$WORK/mise"
_ds_config_dir="$WORK/config"
zsh-defer() { :; }
if [[ $MODE == initialized ]]; then
  autoload -Uz compinit
  compinit -D -i
fi
source "$ROOT/assets/dotfiles/interactive.zsh"
_ds_worktrunk_init() { return 0; }
_ds_completion_init
for tool in bat eza fd rg xh ouch sd yazi ya delta tree-sitter codex; do
  [[ ${_comps[$tool]:-} == _$tool ]] || exit 1
  autoload +X "_$tool" || exit 2
done
'
done
print 'Tool completion checks passed.'
