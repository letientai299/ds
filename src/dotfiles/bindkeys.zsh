[[ -o interactive ]] || return 0
(( ${+_ds_bindkeys_loaded} )) && return 0
typeset -g _ds_bindkeys_loaded=1

bindkey -e
bindkey -s '^k' '| vim -RM -^m'
bindkey -s '^]' '^e | clipcopy^m'
bindkey '^@' autosuggest-accept

# ^w stops at /, ., :, = instead of eating the whole token
_ds_kill_word() {
  local WORDCHARS='_-'
  zle backward-kill-word
}
zle -N _ds_kill_word
bindkey '^w' _ds_kill_word

export EDITOR="${EDITOR:-nvim}"
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^xe' edit-command-line
bindkey '^x^e' edit-command-line
