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
export PATH="$HOME/.local/bin:$XDG_DATA_HOME/mise/shims:$PATH"
[[ -z "${DS_SHELL_PATH:-}" ]] || export PATH="$DS_SHELL_PATH:$PATH"
_ds_root="${DS_SHELL_ROOT:-${${:-$HOME/.local/bin/ds}:A:h}}"
if [[ -z "${DS_SHELL_STATE:-}" && "${_ds_root:h:t}" == versions ]]; then
  _ds_root="${_ds_root:h:h}/current"
fi
export MISE_CACHE_DIR="${MISE_CACHE_DIR:-$XDG_CACHE_HOME/mise}"
export MISE_CONFIG_DIR="$XDG_CONFIG_HOME/ds/mise"
export MISE_DATA_DIR="${MISE_DATA_DIR:-$XDG_DATA_HOME/mise}"
export MISE_STATE_DIR="${MISE_STATE_DIR:-$XDG_STATE_HOME/mise}"
export MISE_SYSTEM_CONFIG_DIR="$XDG_CONFIG_HOME/ds/mise-system"
export MISE_OVERRIDE_CONFIG_FILENAMES=mise.toml
export MISE_GLOBAL_CONFIG_ROOT="$_ds_root/src/mise"
export MISE_TRUSTED_CONFIG_PATHS="$_ds_root/src/mise"
typeset -ga _ds_environments=()
_ds_layer=core
if [[ -r "$XDG_CONFIG_HOME/ds/layer" ]]; then
  _ds_layer="$(<"$XDG_CONFIG_HOME/ds/layer")"
fi
source "${${(%):-%x}:A:h}/profiles.zsh"
for _ds_selected in ${(s:,:)_ds_layer}; do
  _ds_environments+=(${(s:,:)_ds_profiles[$_ds_selected]})
done
unset _ds_profiles
if [[ -r "$XDG_CONFIG_HOME/ds/components" ]]; then
  while IFS= read -r _ds_component; do
    if [[ -n "$_ds_component" && -f "$_ds_root/src/mise/mise.$_ds_component.toml" ]]; then
      _ds_environments+=("$_ds_component")
    fi
  done <"$XDG_CONFIG_HOME/ds/components"
fi
typeset -gaU _ds_environments
export MISE_ENV="${(j:,:)_ds_environments}"
if [[ -S "${XDG_RUNTIME_DIR:-/run/user/$UID}/docker.sock" ]]; then
  export DOCKER_HOST="unix://${XDG_RUNTIME_DIR:-/run/user/$UID}/docker.sock"
fi

# History is deliberately local and independent of plugin managers.
HISTFILE="$XDG_STATE_HOME/zsh/history"
[[ -z "${DS_SHELL_STATE:-}" ]] || HISTFILE="$DS_SHELL_STATE/zsh/history"
source "${${(%):-%x}:A:h}/exports.zsh"
setopt append_history hist_ignore_all_dups hist_ignore_space share_history
setopt interactive_comments no_beep ignore_eof

alias vi=nvim
alias vim=nvim
source "${${(%):-%x}:A:h}/aliases.zsh"
source "${${(%):-%x}:A:h}/bindkeys.zsh"
source "${${(%):-%x}:A:h}/functions.zsh"

source "${${(%):-%x}:A:h}/prompt.zsh"

# Tool-generated initialization is guarded and ordered after static setup. Use
# mise's stable install links directly so initialization does not invoke a shim
# and write config-tracking state during shell startup.
_ds_fzf="$MISE_DATA_DIR/installs/fzf/latest/fzf"
_ds_zoxide="$MISE_DATA_DIR/installs/zoxide/latest/zoxide"
if [[ -x "$_ds_fzf" ]] && (( ! ${+_ds_fzf_loaded} )); then
  source <("$_ds_fzf" --zsh)
  typeset -g _ds_fzf_loaded=1
fi
if [[ -x "$_ds_zoxide" ]] && (( ! ${+_ds_zoxide_loaded} )); then
  eval "$("$_ds_zoxide" init zsh)"
  typeset -g _ds_zoxide_loaded=1
fi
export DS_DS="$_ds_root/ds"
[[ ! -r "$_ds_root/src/dotfiles/command.sh" ]] || source "$_ds_root/src/dotfiles/command.sh"
unset _ds_fzf _ds_zoxide _ds_selected _ds_layer _ds_component _ds_environments _ds_root

[[ ! -r "$XDG_CONFIG_HOME/ds/local.zsh" ]] || source "$XDG_CONFIG_HOME/ds/local.zsh"
if [[ -o interactive && ${DS_MISE_ACTIVATE:-0} == 1 ]] && (( ! ${+_ds_mise_loaded} )); then
  if _ds_activation=$(command mise activate zsh); then
    eval "$_ds_activation" && typeset -g _ds_mise_loaded=1
  fi
  unset _ds_activation
fi
source "${${(%):-%x}:A:h}/interactive.zsh"
