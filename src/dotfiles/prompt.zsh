zmodload zsh/datetime
autoload -Uz add-zsh-hook

# Expand data once; never evaluate repository text.
setopt prompt_subst prompt_percent no_prompt_bang
typeset -g _ds_prompt_git='' _ds_prompt_context='' _ds_prompt_duration='' _ds_prompt_status=''
typeset -gi _ds_prompt_status_width=0
typeset -g _ds_prompt_char='%F{green}❯'
typeset -g _ds_prompt_oid='' _ds_prompt_subject=''
typeset -g _ds_prompt_command=git _ds_prompt_apple_git='' _ds_prompt_apple_key=''
typeset -gF _ds_prompt_started=0
# Reserve one column against automatic wrapping.
PROMPT=$'\n''%$(( COLUMNS > _ds_prompt_status_width + 1 ? COLUMNS - _ds_prompt_status_width - 1 : 1 ))>…>${_ds_prompt_context}%F{cyan}%(5~|…/%4~|%~)%f${_ds_prompt_git}%>>${_ds_prompt_status}
%F{yellow}%(1j.%(2j.%j.)• .)%f${_ds_prompt_duration}%F{yellow}%D{%H:%M:%S}%f ${_ds_prompt_char}%f '
RPROMPT=''

_ds_prompt_preexec() {
  # Exclude time spent editing the command.
  _ds_prompt_started=$EPOCHREALTIME
}

_ds_prompt_resolve_git() {
  emulate -L zsh
  _ds_prompt_command=git
  # Preserve PATH-selected wrappers and alternate installations.
  [[ $OSTYPE == darwin* && ${commands[git]} == /usr/bin/git ]] || return 0
  local selected=/var/db/xcode_select_link
  local key="${(q)DEVELOPER_DIR}:${(q)SDKROOT}:${(q)TOOLCHAINS}:${selected:A}"
  # Re-resolve after developer-tool selection changes.
  if [[ $key != $_ds_prompt_apple_key || ! -x $_ds_prompt_apple_git ]]; then
    _ds_prompt_apple_git=$(/usr/bin/xcrun --find git 2>/dev/null) || _ds_prompt_apple_git=''
    _ds_prompt_apple_key=$key
  fi
  # Avoid Apple's launcher on every refresh.
  [[ ! -x $_ds_prompt_apple_git ]] || _ds_prompt_command=$_ds_prompt_apple_git
  return 0
}

_ds_prompt_git() {
  emulate -L zsh
  local report line branch oid xy sub ahead=0 behind=0 stash=0
  local -i staged=0 changed=0 untracked=0 conflicts=0
  _ds_prompt_git=''
  _ds_prompt_resolve_git
  # Keep fresh counts without index-lock contention.
  report=$(GIT_OPTIONAL_LOCKS=0 command "$_ds_prompt_command" status \
    --porcelain=v2 --branch --ahead-behind --show-stash \
    --untracked-files=normal --ignore-submodules=none 2>/dev/null) || return 0
  # Porcelain quotes newlines inside filenames.
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
        # Submodule dirtiness also counts as unstaged.
        if [[ ${xy[2]} != . || $sub == S*[MU]* ]]; then
          (( ++changed ))
        fi
        ;;
      'u '*) (( ++conflicts )) ;;
      '? '*) (( ++untracked )) ;;
    esac
  done
  [[ $branch != '(detached)' ]] || branch="@${oid[1,8]}"
  # Neutralize terminal controls and prompt escapes.
  branch=${branch//[[:cntrl:]]/ }
  branch=${branch//\%/%%}
  _ds_prompt_git=" %F{magenta}⑂ $branch%f"
  local stats=''
  (( ahead )) && stats+=" %F{cyan}↑$ahead%f"
  (( behind )) && stats+=" %F{blue}↓$behind%f"
  (( staged )) && stats+=" %F{green}+$staged%f"
  (( changed )) && stats+=" %F{yellow}!$changed%f"
  (( untracked )) && stats+=" %F{magenta}?${untracked}%f"
  (( conflicts )) && stats+=" %F{red}×$conflicts%f"
  (( stash )) && stats+=" %F{208}≡$stash%f"
  _ds_prompt_git+=$stats
  # Commit subjects only change with HEAD.
  if [[ $oid != $_ds_prompt_oid ]]; then
    _ds_prompt_subject=''
    if [[ $oid != '(initial)' ]]; then
      # Retry transient failures on subsequent prompts.
      _ds_prompt_subject=$(command "$_ds_prompt_command" log -1 --format=%s --no-show-signature "$oid" -- 2>/dev/null) || {
        _ds_prompt_oid=''
        return 0
      }
    fi
    _ds_prompt_subject=${_ds_prompt_subject//[[:cntrl:]]/ }
    _ds_prompt_oid=$oid
  fi
  if [[ -n $_ds_prompt_subject ]]; then
    local subject=${_ds_prompt_subject//\%/%%}
    [[ $_ds_prompt_subject == WIP* ]] && subject="%B%F{red}WIP%f%b${subject[4,-1]}"
    _ds_prompt_git+=" %f${subject}%f"
  fi
  return 0
}

_ds_prompt_context() {
  emulate -L zsh
  local context='' ssh_alias=${LC_SSH_ALIAS:-${HOST%%.*}}
  local line mountpoint options super_options physical_pwd
  local -a fields
  local -i separator index best_length=0 readonly_mount=0

  if [[ -n ${SSH_CONNECTION:-}${SSH_TTY:-} ]]; then
    ssh_alias=${ssh_alias//[[:cntrl:]]/ }
    ssh_alias=${ssh_alias//\%/%%}
    context+="%F{blue}[$ssh_alias]%f "
  fi
  (( EUID == 0 )) && context+='%F{red}⚙️%f '

  if [[ $OSTYPE == linux* && -r /proc/self/mountinfo ]]; then
    physical_pwd=${PWD:A}
    while IFS= read -r line; do
      fields=("${(@s: :)line}")
      (( $#fields >= 10 )) || continue
      separator=0
      for (( index=7; index <= $#fields; ++index )); do
        if [[ ${fields[index]} == '-' ]]; then
          separator=$index
          break
        fi
      done
      (( separator > 0 && separator + 3 <= $#fields )) || continue
      mountpoint=${fields[5]}
      mountpoint=${mountpoint//\\040/$' '}
      mountpoint=${mountpoint//\\011/$'\t'}
      mountpoint=${mountpoint//\\012/$'\n'}
      mountpoint=${mountpoint//\\134/$'\\'}
      if [[ $physical_pwd != $mountpoint && $mountpoint != / && $physical_pwd != "$mountpoint"/* ]]; then
        continue
      fi
      options=${fields[6]}
      super_options=${fields[separator + 3]}
      if (( ${#mountpoint} > best_length )); then
        best_length=${#mountpoint}
        if [[ ",$options," == *,ro,* || ",$super_options," == *,ro,* ]]; then
          readonly_mount=1
        else
          readonly_mount=0
        fi
      fi
    done < /proc/self/mountinfo
  fi
  (( readonly_mount )) && context+='%F{yellow}🔒%f '

  _ds_prompt_context=$context
}

_ds_prompt_precmd() {
  # Capture status before any command overwrites it.
  local -i code=$?
  emulate -L zsh
  local -F elapsed=0
  (( _ds_prompt_started )) && elapsed=$(( EPOCHREALTIME - _ds_prompt_started ))
  # Empty prompts must not reuse command duration.
  _ds_prompt_started=0
  _ds_prompt_duration=''
  if (( elapsed > 10 )); then
    local -i seconds=$elapsed
    local duration="${seconds}s"
    (( seconds < 60 )) || duration="$(( seconds / 60 ))m$(( seconds % 60 ))s"
    _ds_prompt_duration="%F{yellow}$duration%f "
  fi
  _ds_prompt_char='%F{green}❯'
  _ds_prompt_status=''
  _ds_prompt_status_width=0
  if (( code != 0 )); then
    _ds_prompt_status=" %F{red}[$code]%f"
    _ds_prompt_status_width=$(( 3 + ${#code} ))
    _ds_prompt_char='%F{red}❯'
  fi
  _ds_prompt_context
  _ds_prompt_git
  return 0
}

add-zsh-hook preexec _ds_prompt_preexec
add-zsh-hook precmd _ds_prompt_precmd
