j() {
  emulate -L zsh
  setopt pipefail
  local root result
  root=$(git rev-parse --show-toplevel 2>/dev/null) || root=$PWD
  if (( $# && $+commands[zoxide] )); then
    for result in "${(@f)$(zoxide query --list -- "$@" 2>/dev/null)}"; do
      if [[ $result == "$root"/* && -d $result ]]; then
        builtin cd -- "$result"
        return
      fi
    done
  fi
  result=$(builtin cd -- "$root" && fzf-dirs | fzf --height 40% --reverse \
    --query "$*" --preview 'ls -1A -- {}') || return $?
  [[ -n $result ]] && builtin cd -- "$root/$result"
}

local_todo() {
  local common root
  common=$(git rev-parse --path-format=absolute --git-common-dir) || return $?
  root=$common
  [[ ${common:t} != .git ]] || root=${common:h}
  mkdir -p -- "$root/.dump" || return $?
  "${EDITOR:-nvim}" "$root/.dump/todo.md"
}

_ds_worktrunk_init() {
  [[ ,${MISE_ENV:-}, == *,extra,* ]] || return 1
  (( ${+_ds_worktrunk_loaded} )) && return 0
  local -a binaries=("$MISE_DATA_DIR"/installs/http-worktrunk/latest/{,bin/,*/}wt(N))
  (( $#binaries )) || return 1
  local script
  script=$("$binaries[1]" config shell init zsh) || return $?
  [[ -n $script ]] || return 1
  eval "$script" || return $?
  typeset -g _ds_worktrunk_loaded=1
}

if (( ! $+functions[wt] )); then
  wt() {
    if ! _ds_worktrunk_init; then
      print -ru2 -- 'wt: install Worktrunk with ds apply extra'
      return 1
    fi
    wt "$@"
  }
fi
