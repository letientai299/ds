# Static environment and paths.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
# shell-init re-sources this file from inside the `ds` function, so the
# declaration has to be global: a function-local PATH starts empty, and the
# export below would then leave a trailing colon that puts $PWD on PATH. -U
# keeps the first occurrence, which leaves the ds entries in front.
typeset -gU path PATH
_ds_root="${DS_SHELL_ROOT:-${${:-$HOME/.local/bin/ds}:A:h}}"
if [[ -z "${DS_SHELL_STATE:-}" && "${_ds_root:h:t}" == versions ]]; then
  _ds_root="${_ds_root:h:h}/current"
fi
export MISE_CACHE_DIR="${MISE_CACHE_DIR:-$XDG_CACHE_HOME/mise}"
export MISE_CONFIG_DIR="${MISE_CONFIG_DIR:-$XDG_CONFIG_HOME/mise}"
if [[ ${MISE_GLOBAL_CONFIG_FILE:-} == */src/mise/mise.toml ]]; then
  unset MISE_GLOBAL_CONFIG_FILE
fi
export MISE_DATA_DIR="${MISE_DATA_DIR:-$XDG_DATA_HOME/mise}"
export PATH="$HOME/.local/bin:$MISE_DATA_DIR/shims:$PATH"
[[ -z "${DS_SHELL_PATH:-}" ]] || export PATH="$DS_SHELL_PATH:$PATH"
export MISE_STATE_DIR="${MISE_STATE_DIR:-$XDG_STATE_HOME/mise}"
export MISE_SYSTEM_CONFIG_DIR="$XDG_CONFIG_HOME/ds/mise-system"
unset MISE_OVERRIDE_CONFIG_FILENAMES
if [[ ":${MISE_CEILING_PATHS:-}:" != *":$HOME:"* ]]; then
  export MISE_CEILING_PATHS="$HOME${MISE_CEILING_PATHS:+:$MISE_CEILING_PATHS}"
fi
if [[ ${MISE_GLOBAL_CONFIG_ROOT:-} == */src/mise ]]; then
  unset MISE_GLOBAL_CONFIG_ROOT
fi
export MISE_TRUSTED_CONFIG_PATHS="${MISE_TRUSTED_CONFIG_PATHS:-$_ds_root/src/mise}"
_ds_layer=core
if [[ -r "$XDG_CONFIG_HOME/ds/layer" ]]; then
  _ds_layer="$(<"$XDG_CONFIG_HOME/ds/layer")"
fi
typeset -g _ds_layers=$_ds_layer
export MISE_ENV="${MISE_ENV:-}"
if [[ -n "${DS_SHELL_STATE:-}" && -r "$MISE_CONFIG_DIR/config.personal.toml" ]]; then
  export MISE_ENV=personal
fi
if [[ ,$_ds_layer, == *,remote,* || ,$_ds_layer, == *,all,* ]]; then
  export YAZI_CONFIG_HOME="$XDG_CONFIG_HOME/ds/yazi"
fi
if [[ -S "${XDG_RUNTIME_DIR:-/run/user/$UID}/docker.sock" ]]; then
  export DOCKER_HOST="unix://${XDG_RUNTIME_DIR:-/run/user/$UID}/docker.sock"
fi

# History is deliberately local and independent of plugin managers.
HISTFILE="$XDG_STATE_HOME/zsh/history"
[[ -z "${DS_SHELL_STATE:-}" ]] || HISTFILE="$DS_SHELL_STATE/zsh/history"
source "${${(%):-%x}:A:h}/exports.zsh"
setopt append_history hist_ignore_all_dups hist_ignore_space hist_verify share_history
setopt complete_in_word interactive_comments no_beep ignore_eof

alias vi=nvim
alias vim=nvim
source "${${(%):-%x}:A:h}/aliases.zsh"
source "${${(%):-%x}:A:h}/bindkeys.zsh"
source "${${(%):-%x}:A:h}/functions.zsh"

source "${${(%):-%x}:A:h}/prompt.zsh"

export DS_DS="$_ds_root/ds"
[[ ! -r "$_ds_root/src/dotfiles/command.sh" ]] || source "$_ds_root/src/dotfiles/command.sh"
unset _ds_selected _ds_layer _ds_component _ds_environments _ds_root

[[ ! -r "$XDG_CONFIG_HOME/ds/local.zsh" ]] || source "$XDG_CONFIG_HOME/ds/local.zsh"
source "${${(%):-%x}:A:h}/interactive.zsh"
