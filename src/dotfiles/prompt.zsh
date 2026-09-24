zmodload zsh/datetime
autoload -Uz add-zsh-hook

# Expand data once; never evaluate repository text.
setopt prompt_subst prompt_percent no_prompt_bang
typeset -g _ds_prompt_git='' _ds_prompt_duration='' _ds_prompt_char='%F{green}❯'
typeset -g _ds_prompt_oid='' _ds_prompt_subject=''
typeset -gF _ds_prompt_started=0
PROMPT='%$(( COLUMNS > 1 ? COLUMNS - 1 : 1 ))>…>%F{blue}%(5~|…/%4~|%~)%f${_ds_prompt_git}%>>
%F{yellow}%(1j.%(2j.%j.)• .)%f${_ds_prompt_duration}%F{yellow}%D{%H:%M:%S}%f ${_ds_prompt_char}%f '
RPROMPT=''

_ds_prompt_preexec() {
  _ds_prompt_started=$EPOCHREALTIME
}

_ds_prompt_git() {
  emulate -L zsh
  local report line branch oid xy sub ahead=0 behind=0 stash=0
  local -i staged=0 changed=0 untracked=0 conflicts=0
  _ds_prompt_git=''
  report=$(GIT_OPTIONAL_LOCKS=0 command git status --porcelain=v2 --branch --ahead-behind --show-stash --untracked-files=normal --ignore-submodules=none 2>/dev/null) || return 0
  for line in ${(f)report}; do
    case $line in
      '# branch.head '*) branch=${line#\# branch.head } ;;
      '# branch.oid '*) oid=${line#\# branch.oid } ;;
      '# branch.ab '*)
        ahead=${${line#*+}%% *}
        behind=${line##*-}
        ;;
      '# stash '*) stash=${line##* } ;;
      '1 '*|'2 '*)
        xy=${${line#? }%% *}
        sub=${${line#?????}%% *}
        [[ ${xy[1]} == . ]] || (( ++staged ))
        if [[ ${xy[2]} != . || $sub == S*[MU]* ]]; then
          (( ++changed ))
        fi
        ;;
      'u '*) (( ++conflicts )) ;;
      '? '*) (( ++untracked )) ;;
    esac
  done
  [[ $branch != '(detached)' ]] || branch="@${oid[1,8]}"
  branch=${branch//[[:cntrl:]]/ }
  branch=${branch//\%/%%}
  _ds_prompt_git=" %F{magenta}⑂ $branch%f"
  local stats=''
  (( ahead )) && stats+=" ↑$ahead"
  (( behind )) && stats+=" ↓$behind"
  (( staged )) && stats+=" +$staged"
  (( changed )) && stats+=" !$changed"
  (( untracked )) && stats+=" ?$untracked"
  (( conflicts )) && stats+=" ×$conflicts"
  (( stash )) && stats+=" ≡$stash"
  [[ -z $stats ]] || _ds_prompt_git+="%F{yellow}$stats%f"
  if [[ $oid != $_ds_prompt_oid ]]; then
    _ds_prompt_subject=''
    if [[ $oid != '(initial)' ]]; then
      _ds_prompt_subject=$(command git log -1 --format=%s --no-show-signature "$oid" -- 2>/dev/null)
    fi
    _ds_prompt_subject=${_ds_prompt_subject//[[:cntrl:]]/ }
    _ds_prompt_oid=$oid
  fi
  if [[ -n $_ds_prompt_subject ]]; then
    _ds_prompt_git+=" %f${_ds_prompt_subject//\%/%%}%f"
  fi
  return 0
}

_ds_prompt_precmd() {
  local -i code=$?
  emulate -L zsh
  local -F elapsed=0
  (( _ds_prompt_started )) && elapsed=$(( EPOCHREALTIME - _ds_prompt_started ))
  _ds_prompt_started=0
  _ds_prompt_duration=''
  if (( elapsed > 10 )); then
    local -i seconds=$elapsed
    local duration="${seconds}s"
    (( seconds < 60 )) || duration="$(( seconds / 60 ))m$(( seconds % 60 ))s"
    _ds_prompt_duration="%F{yellow}$duration%f "
  fi
  _ds_prompt_char='%F{green}❯'
  (( code == 0 )) || _ds_prompt_char="%F{red}[$code]❯"
  _ds_prompt_git
  return 0
}

add-zsh-hook preexec _ds_prompt_preexec
add-zsh-hook precmd _ds_prompt_precmd
