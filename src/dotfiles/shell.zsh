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
_ds_root="${DS_SHELL_ROOT:-${${:-$HOME/.local/bin/ds}:A:h}}"
if [[ "${_ds_root:h:t}" == versions ]]; then
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
typeset -a _ds_environments
_ds_layer=core
if [[ -r "$XDG_CONFIG_HOME/ds/layer" ]]; then
  _ds_layer="$(<"$XDG_CONFIG_HOME/ds/layer")"
fi
[[ "$_ds_layer" != core ]] || _ds_layer=core
[[ "$_ds_layer" != remote ]] || _ds_environments+=(remote)
if [[ -r "$XDG_CONFIG_HOME/ds/components" ]]; then
  while IFS= read -r _ds_component; do
    [[ -z "$_ds_component" ]] || _ds_environments+=("$_ds_component")
  done <"$XDG_CONFIG_HOME/ds/components"
fi
export MISE_ENV="${(j:,:)_ds_environments}"
if [[ -S "${XDG_RUNTIME_DIR:-/run/user/$UID}/docker.sock" ]]; then
  export DOCKER_HOST="unix://${XDG_RUNTIME_DIR:-/run/user/$UID}/docker.sock"
fi

# History is deliberately local and independent of plugin managers.
HISTFILE="$XDG_STATE_HOME/zsh/history"
HISTSIZE=100000
SAVEHIST=100000
setopt append_history hist_ignore_all_dups hist_ignore_space share_history

alias vi=nvim
alias vim=nvim
source "${${(%):-%x}:A:h}/aliases.zsh"

# Minimal two-line prompt. Optional Starship replaces this when installed.
PROMPT='%F{cyan}%n@%m%f %F{blue}%~%f
%(?.%F{green}.%F{red})❯%f '

# Keep nnn in the current shell after quitting with q.
n() {
  local lastdir="$XDG_STATE_HOME/nnn/lastdir"
  mkdir -p "${lastdir:h}"
  NNN_TMPFILE="$lastdir" command nnn "$@"
  if [[ -s "$lastdir" ]]; then
    source "$lastdir"
    rm -f "$lastdir"
  fi
}

# Tool-generated initialization is guarded and ordered after static setup. Use
# mise's stable install links directly so initialization does not invoke a shim
# and write config-tracking state during shell startup.
_ds_fzf="$MISE_DATA_DIR/installs/fzf/latest/fzf"
_ds_zoxide="$MISE_DATA_DIR/installs/zoxide/latest/zoxide"
_ds_starship="$MISE_DATA_DIR/installs/starship/latest/starship"
if [[ -x "$_ds_fzf" ]]; then
  source <("$_ds_fzf" --zsh)
fi
if [[ "$_ds_layer" == remote && -x "$_ds_zoxide" ]]; then
  eval "$("$_ds_zoxide" init zsh)"
fi
if (( ${_ds_environments[(Ie)starship]} )) && [[ -x "$_ds_starship" ]]; then
  eval "$("$_ds_starship" init zsh)"
fi
export DS_DS="$_ds_root/ds"
[[ ! -r "$_ds_root/src/dotfiles/command.sh" ]] || source "$_ds_root/src/dotfiles/command.sh"
unset _ds_fzf _ds_zoxide _ds_starship _ds_layer _ds_component _ds_environments _ds_root

[[ ! -r "$XDG_CONFIG_HOME/ds/local.zsh" ]] || source "$XDG_CONFIG_HOME/ds/local.zsh"
