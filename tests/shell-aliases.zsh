#!/usr/bin/env zsh
setopt err_exit no_unset pipe_fail
root=${0:A:h:h}
work=$(mktemp -d)
trap 'command rm -rf -- "$work"' EXIT

fail() {
  print -ru2 -- "$1"
  exit 1
}

(
  _ds_config_dir="$work/config"
  path=()
  commands[nvim]=/usr/bin/true
  commands[vim]=/usr/bin/true
  commands[ouch]=/usr/bin/true
  unset EDITOR
  source "$root/assets/dotfiles/exports.zsh"
  [[ $EDITOR == nvim ]] || fail 'Neovim fallback failed'
  unset EDITOR 'commands[nvim]'
  source "$root/assets/dotfiles/exports.zsh"
  [[ $EDITOR == vim ]] || fail 'Vim fallback failed'
  unset EDITOR 'commands[vim]'
  source "$root/assets/dotfiles/exports.zsh"
  [[ $EDITOR == vi ]] || fail 'Vi fallback failed'
  export EDITOR='custom-editor --wait'
  source "$root/assets/dotfiles/exports.zsh"
  [[ $EDITOR == 'custom-editor --wait' ]] || fail 'Editor override lost'
  unsetopt no_unset
  source "$root/assets/dotfiles/aliases.zsh"
  [[ ${aliases[extract]} == 'ouch decompress' ]] || fail 'Extract alias missing'
  unset 'commands[ouch]'
  source "$root/assets/dotfiles/aliases.zsh"
  (( ! $+aliases[extract] )) || fail 'Extract alias remained'
  alias extract='custom-extract'
  source "$root/assets/dotfiles/aliases.zsh"
  [[ ${aliases[extract]} == custom-extract ]] || fail 'Custom extract lost'
)

print 'Shell alias checks passed.'
