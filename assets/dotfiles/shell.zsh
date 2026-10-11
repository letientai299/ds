# Static environment and paths.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
# Declared global so re-sourcing from a function keeps PATH intact; -U keeps
# the first occurrence, which leaves the ds entries in front.
typeset -gU path PATH
# The directory holding this link is the ds configuration of this home or
# trial; the resolved directory holds the assets.
typeset -g _ds_config_dir="${${(%):-%x}:h}"
export MISE_CACHE_DIR="${MISE_CACHE_DIR:-$XDG_CACHE_HOME/mise}"
export MISE_CONFIG_DIR="${MISE_CONFIG_DIR:-$XDG_CONFIG_HOME/mise}"
export MISE_DATA_DIR="${MISE_DATA_DIR:-$XDG_DATA_HOME/mise}"
export MISE_STATE_DIR="${MISE_STATE_DIR:-$XDG_STATE_HOME/mise}"
export MISE_MINIMUM_RELEASE_AGE=0s
export PATH="$HOME/.local/bin:$MISE_DATA_DIR/shims:$PATH"
[[ -z "${DS_TRIAL:-}" ]] || export PATH="$DS_TRIAL/bin:$PATH"
if [[ ":${MISE_CEILING_PATHS:-}:" != *":$HOME:"* ]]; then
  export MISE_CEILING_PATHS="$HOME${MISE_CEILING_PATHS:+:$MISE_CEILING_PATHS}"
fi
[[ ! -d "$_ds_config_dir/yazi" ]] || export YAZI_CONFIG_HOME="$_ds_config_dir/yazi"

# History is deliberately local and independent of plugin managers.
HISTFILE="$XDG_STATE_HOME/zsh/history"
[[ -z "${DS_TRIAL:-}" ]] || HISTFILE="$DS_TRIAL/zsh/history"
[[ -d ${HISTFILE:h} ]] || mkdir -p -- "${HISTFILE:h}"
source "${${(%):-%x}:A:h}/exports.zsh"
setopt append_history hist_ignore_all_dups hist_ignore_space hist_verify share_history
setopt complete_in_word interactive_comments no_beep ignore_eof

alias vi=nvim
alias vim=nvim
source "${${(%):-%x}:A:h}/aliases.zsh"
source "${${(%):-%x}:A:h}/bindkeys.zsh"
source "${${(%):-%x}:A:h}/functions.zsh"

source "${${(%):-%x}:A:h}/prompt.zsh"

[[ ! -r "$XDG_CONFIG_HOME/ds/local.zsh" ]] || source "$XDG_CONFIG_HOME/ds/local.zsh"
source "${${(%):-%x}:A:h}/interactive.zsh"
