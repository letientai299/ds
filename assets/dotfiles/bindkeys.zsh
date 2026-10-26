[[ -o interactive ]] || return 0
(( ${+_ds_bindkeys_loaded} )) && return 0
typeset -g _ds_bindkeys_loaded=1

bindkey -e
bindkey -s '^k' '| vim -RM -^m'
bindkey -s '^]' '^e | clipcopy^m'
bindkey '^@' autosuggest-accept

# Keep punctuation separate when deleting words.
_ds_kill_word() {
  zle -f kill
  zle vi-backward-kill-word
}
zle -N _ds_kill_word
bindkey '^w' _ds_kill_word
bindkey '^[^?' _ds_kill_word
bindkey '^[^H' _ds_kill_word

_ds_kill_forward_word() {
  local start=$CURSOR previous=$LASTWIDGET word
  zle -f kill
  zle .vi-forward-word
  word=${BUFFER[start+1,CURSOR]}
  CURSOR=$start
  [[ -n $word ]] || return 0
  if [[ $previous == *kill* ]]; then
    CUTBUFFER+=$word
  else
    zle .copy-region-as-kill -- "$word"
  fi
  RBUFFER=${RBUFFER[${#word}+1,-1]}
}
zle -N _ds_kill_forward_word
bindkey '^[d' _ds_kill_forward_word
bindkey '^[[3;3~' _ds_kill_forward_word

bindkey '^[[1;5D' vi-backward-word
bindkey '^[[1;5C' vi-forward-word
bindkey '^[[1;3D' vi-backward-word
bindkey '^[[1;3C' vi-forward-word
bindkey '^[^[[D' vi-backward-word
bindkey '^[^[[C' vi-forward-word
bindkey '^[b' vi-backward-word
bindkey '^[f' vi-forward-word
bindkey '^_' undo
bindkey '^[_' redo

export EDITOR="${EDITOR:-nvim}"
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^xe' edit-command-line
bindkey '^x^e' edit-command-line
