[[ -o interactive && -o zle ]] || return 0
(( ${+_ds_plugins_queued} )) && return 0
typeset -g _ds_plugins_queued=1
typeset -g _ds_plugins_dir="${${(%):-%x}:A:h}/plugins"
typeset -gU fpath
fpath=("$HOME/.local/share/zsh/site-functions" "$XDG_DATA_HOME/zsh/site-functions"
  "${_ds_plugins_dir:h}/completions" "$_ds_plugins_dir/zsh-completions/src" $fpath)

if (( ! $+functions[zsh-defer] )); then
  source "$_ds_plugins_dir/zsh-defer/zsh-defer.plugin.zsh"
fi

_ds_completion_init() {
  if (( ! $+functions[compdef] )); then
    local cache="$XDG_CACHE_HOME/ds/zsh"
    local revision="$(<"$_ds_plugins_dir/zsh-completions/REVISION")"
    revision=${revision##*$'\n'}
    mkdir -p "$cache"
    autoload -Uz compinit
    compinit -i -d "$cache/zcompdump-$ZSH_VERSION-$revision"
  else
    local definition header
    for definition in "$_ds_plugins_dir"/zsh-completions/src/_*(N); do
      IFS= read -r header < "$definition"
      [[ $header == '#compdef '* ]] || continue
      compdef -na "${definition:t}" ${=header#\#compdef }
    done
  fi
  unfunction _ssh_hosts 2>/dev/null
  autoload -Uz _ssh_hosts
  if [[ -x "$DS_DS" ]]; then
    source <("$DS_DS" completion zsh)
  fi
  _ds_worktrunk_init || true
  if (( $+functions[_wt_lazy_complete] )); then
    compdef _wt_lazy_complete wt
  fi
}

_ds_fzf_tab_init() {
  (( $+commands[fzf] && ! $+functions[enable-fzf-tab] )) || return 0
  zstyle ':completion:*' menu no
  source "$_ds_plugins_dir/fzf-tab/fzf-tab.plugin.zsh"
}

_ds_autosuggestions_init() {
  (( $+functions[_zsh_autosuggest_start] )) && return 0
  : ${ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE:=1000}
  source "$_ds_plugins_dir/zsh-autosuggestions/zsh-autosuggestions.zsh"
  _zsh_autosuggest_start
}

_ds_highlighting_init() {
  if (( ! $+functions[_zsh_highlight] )); then
    : ${ZSH_HIGHLIGHT_MAXLENGTH:=10000}
    source "$_ds_plugins_dir/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
  fi
  typeset -g _ds_plugins_ready=1
}

# Wait for idle ZLE after the first prompt. Keep errors visible, without
# replaying directory or prompt hooks; highlighting must follow widget setup.
zsh-defer -dm2 _ds_completion_init
zsh-defer -dm2 _ds_fzf_tab_init
zsh-defer -dm2 _ds_autosuggestions_init
zsh-defer -dm2 _ds_highlighting_init
