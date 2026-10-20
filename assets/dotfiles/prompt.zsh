zmodload zsh/datetime
autoload -Uz add-zsh-hook

# Expand data once; never evaluate repository text.
setopt prompt_subst prompt_percent no_prompt_bang
typeset -g _ds_prompt_git='' _ds_prompt_context='' _ds_prompt_duration='' _ds_prompt_status=''
typeset -g _ds_prompt_path='%F{cyan}%(5~|…/%4~|%~)%f'
typeset -g _ds_prompt_root='' _ds_prompt_pwd='' _ds_prompt_branch='' _ds_prompt_root_branch='' _ds_prompt_physical=''
typeset -g _ds_prompt_mr='' _ds_prompt_mr_key=''
typeset -gA _ds_prompt_mr_values _ds_prompt_mr_expiry _ds_prompt_mr_pending _ds_prompt_mr_fds
typeset -gi _ds_prompt_status_width=0
typeset -g _ds_prompt_char='%F{green}❯'
typeset -g _ds_prompt_oid='' _ds_prompt_subject=''
typeset -g _ds_prompt_command=git _ds_prompt_apple_git='' _ds_prompt_apple_key=''
typeset -gF _ds_prompt_started=0
typeset -g _ds_prompt_async_fd=${_ds_prompt_async_fd:-} _ds_prompt_async_key=''
typeset -g _ds_prompt_cache_file='' _ds_prompt_cache_key=''
typeset -gi _ds_prompt_generation=${_ds_prompt_generation:-0} _ds_prompt_pending_generation=${_ds_prompt_pending_generation:-0}
# Reserve one column against automatic wrapping.
PROMPT=$'\n''%$(( COLUMNS > _ds_prompt_status_width + 1 ? COLUMNS - _ds_prompt_status_width - 1 : 1 ))>…>${_ds_prompt_mr}${_ds_prompt_context}${_ds_prompt_path}${_ds_prompt_git}%>>${_ds_prompt_status}
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
  _ds_prompt_branch=''
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
  [[ $branch == '(detached)' ]] || _ds_prompt_branch=$branch
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
    _ds_prompt_git+=" %f${subject}%f %F{242}${oid[1,8]}%f"
  fi
  return 0
}

_ds_prompt_path() {
  emulate -L zsh
  _ds_prompt_path='%F{cyan}%(5~|…/%4~|%~)%f'
  if [[ -z $_ds_prompt_git ]]; then
    _ds_prompt_root=''
    _ds_prompt_pwd=''
    return 0
  fi
  local physical=$_ds_prompt_physical
  [[ $PWD == $_ds_prompt_pwd ]] || physical=${PWD:A}
  if [[ $PWD != $_ds_prompt_pwd || $_ds_prompt_branch != $_ds_prompt_root_branch || -z $_ds_prompt_root || ( -e $PWD/.git && $physical != $_ds_prompt_root ) ]]; then
    local directory=$physical gitdir config='' common
    while [[ $directory != / && ! -e $directory/.git ]]; do
      directory=${directory:h}
    done
    gitdir=$directory/.git
    if [[ -f $gitdir ]]; then
      read -r common < "$gitdir"
      gitdir=${common#gitdir: }
      [[ $gitdir == /* ]] || gitdir="$directory/$gitdir"
    fi
    [[ ! -r $gitdir/config.worktree ]] || config=$(<"$gitdir/config.worktree")
    if [[ -r $gitdir/commondir ]]; then
      read -r common < "$gitdir/commondir"
      [[ $common == /* ]] || common="$gitdir/$common"
      gitdir=$common
    fi
    [[ ! -r $gitdir/config ]] || config+=$(<"$gitdir/config")
    # Custom worktrees require Git's own resolution.
    if [[ -n ${GIT_DIR:-}${GIT_WORK_TREE:-} || ! -d $gitdir || ${(L)config} =~ $'(^|\n)[ \t]*worktree[ \t]*=' || ${(L)config} == *'[include'* ]]; then
      _ds_prompt_root=$(command "$_ds_prompt_command" rev-parse --show-toplevel 2>/dev/null) || return 0
    else
      _ds_prompt_root=$directory
    fi
    _ds_prompt_pwd=$PWD
    _ds_prompt_root_branch=$_ds_prompt_branch
    _ds_prompt_physical=$physical
  fi
  local name=${_ds_prompt_root:t} suffix
  [[ $physical == $_ds_prompt_root || $physical == "$_ds_prompt_root"/* ]] || return 0
  suffix=${physical#"$_ds_prompt_root"}
  name=${name//[[:cntrl:]]/ }
  suffix=${suffix//[[:cntrl:]]/ }
  _ds_prompt_path="%B%F{blue}${name//\%/%%}%b%F{cyan}${suffix//\%/%%}%f"
}

_ds_prompt_mr_render() {
  emulate -L zsh
  local value=${_ds_prompt_mr_values[$_ds_prompt_mr_key]}
  local iid=${value%% *} url=${value#* }
  _ds_prompt_mr=''
  [[ $iid == <1-> && $url == http(s|)://* && $url != *[[:cntrl:][:space:]]* ]] || return 0
  url=${url//\%/%%}
  _ds_prompt_mr=$'%F{green}%{\e]8;;'"$url"$'\e\\%}!'"$iid"$'%{\e]8;;\e\\%}%f '
}

_ds_prompt_mr_fetch() {
  emulate -L zsh
  local file=$1 branch=$2 result iid url cached
  local -i expiry=$(( EPOCHSECONDS + 60 ))
  if [[ -r $file ]] && read -r cached result < "$file" && [[ $cached == <-> ]] && (( cached > EPOCHSECONDS )); then
    print -r -- "$cached $result"
    return 0
  fi
  if result=$(command glab mr list --source-branch "$branch" --per-page 1 \
      --output json --jq 'if length == 0 then "0" else .[0] | "\(.iid) \(.web_url)" end' 2>/dev/null </dev/null); then
    read -r iid url <<< "$result"
    if [[ $iid == 0 ]]; then
      expiry=$(( EPOCHSECONDS + 300 ))
    elif [[ $iid == <1-> && $url == http(s|)://* && $url != *[[:cntrl:][:space:]]* ]]; then
      expiry=$(( EPOCHSECONDS + 60 ))
    else
      result=''
    fi
  else
    result=''
  fi
  local record="$expiry $result"
  # Atomic writes keep simultaneous shells independent.
  (
    umask 077
    command mkdir -p -- "${file:h}" &&
      print -r -- "$record" > "$file.$$.tmp" &&
      command mv -f -- "$file.$$.tmp" "$file"
  ) 2>/dev/null
  print -r -- "$record"
}

_ds_prompt_mr_ready() {
  emulate -L zsh
  local fd=$1 key=${_ds_prompt_mr_fds[$1]} expiry result
  if read -r -u "$fd" expiry result && [[ $expiry == <-> ]]; then
    _ds_prompt_mr_expiry[$key]=$expiry
    _ds_prompt_mr_values[$key]=$result
  else
    _ds_prompt_mr_expiry[$key]=$(( EPOCHSECONDS + 60 ))
    _ds_prompt_mr_values[$key]=''
  fi
  zle -F "$fd"
  exec {fd}<&-
  unset "_ds_prompt_mr_fds[$1]" "_ds_prompt_mr_pending[$key]"
  if [[ $key == $_ds_prompt_mr_key ]]; then
    _ds_prompt_mr_render
    zle && zle reset-prompt
  fi
  return 0
}

_ds_prompt_mr() {
  emulate -L zsh
  _ds_prompt_mr=''
  _ds_prompt_mr_key=''
  [[ -n $_ds_prompt_git && -n $_ds_prompt_root && -n $_ds_prompt_branch ]] || return 0
  (( $+commands[glab] )) || return 0
  local branch=${_ds_prompt_branch//\%/%25} fd
  _ds_prompt_mr_key="${XDG_CACHE_HOME:-$HOME/.cache}/ds/prompt-mr-open${_ds_prompt_root}/branches/$branch/entry"
  local key=$_ds_prompt_mr_key
  if (( ${_ds_prompt_mr_expiry[$key]:-0} > EPOCHSECONDS )); then
    _ds_prompt_mr_render
    return 0
  fi
  # Only interactive shells have descriptor callbacks.
  [[ -o interactive && -z ${_ds_prompt_mr_pending[$key]} ]] || return 0
  exec {fd}< <(_ds_prompt_mr_fetch "$key" "$_ds_prompt_branch")
  _ds_prompt_mr_fds[$fd]=$key
  _ds_prompt_mr_pending[$key]=$fd
  zle -F "$fd" _ds_prompt_mr_ready
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

_ds_prompt_cache_location() {
  emulate -L zsh
  local relative=${PWD#/} directory="${XDG_CACHE_HOME:-$HOME/.cache}/ds/prompt-v2/$EUID"
  # Separate child directories from cached records.
  [[ -z $relative ]] || directory+="/d/${relative//\//\/d\/}"
  _ds_prompt_cache_file="$directory/entry"
  _ds_prompt_cache_key="${(q)PWD}:${(q)GIT_DIR}:${(q)GIT_WORK_TREE}:${(q)GIT_INDEX_FILE}:${(q)HOST}:${(q)LC_SSH_ALIAS}:${SSH_CONNECTION:+ssh}:${SSH_TTY:+tty}"
}

_ds_prompt_cache_read() {
  emulate -L zsh
  local line file=$_ds_prompt_cache_file
  local -a values
  # Preserve existing caches during layout migration.
  [[ -f $file ]] || file="${XDG_CACHE_HOME:-$HOME/.cache}/ds/prompt-v1/$EUID${PWD}/entry"
  # Ignore incomplete records and special files.
  [[ -f $file && -r $file ]] || return 0
  IFS= read -r line < "$file" || return 0
  values=("${(@ps:\t:)line}")
  values=("${(@Q)values}")
  (( $#values == 4 )) && [[ $values[1] == $_ds_prompt_cache_key ]] || return 0
  _ds_prompt_context=$values[2]
  _ds_prompt_git=$values[3]
  _ds_prompt_path=$values[4]
}

_ds_prompt_cache_write() {
  emulate -L zsh
  [[ -n $_ds_prompt_cache_file && ! -d $_ds_prompt_cache_file ]] || return 0
  local -a values=("$_ds_prompt_cache_key" "$_ds_prompt_context" "$_ds_prompt_git" "$_ds_prompt_path")
  local record="${(pj:\t:)${(@qqqq)values}}" cached
  if [[ -f $_ds_prompt_cache_file ]] && IFS= read -r cached < "$_ds_prompt_cache_file" && [[ $cached == $record ]]; then
    return 0
  fi
  (
    umask 077
    command mkdir -p -- "${_ds_prompt_cache_file:h}" || return 0
    local temporary="$_ds_prompt_cache_file.$$.tmp"
    if print -r -- "$record" > "$temporary" && command mv -f -- "$temporary" "$_ds_prompt_cache_file"; then
      return 0
    fi
    command rm -f -- "$temporary"
  ) 2>/dev/null
  return 0
}

_ds_prompt_snapshot() {
  emulate -L zsh
  _ds_prompt_context
  _ds_prompt_git
  _ds_prompt_path
  _ds_prompt_cache_write
  local -a values=(
    "$_ds_prompt_context" "$_ds_prompt_git" "$_ds_prompt_path"
    "$_ds_prompt_root" "$_ds_prompt_pwd" "$_ds_prompt_branch"
    "$_ds_prompt_root_branch" "$_ds_prompt_physical"
    "$_ds_prompt_oid" "$_ds_prompt_subject" "$_ds_prompt_command"
    "$_ds_prompt_apple_git" "$_ds_prompt_apple_key"
  )
  # Quote data without evaluating repository text.
  print -r -- "${(pj:\t:)${(@qqqq)values}}"
}

_ds_prompt_async_ready() {
  emulate -L zsh
  local fd=$1 line
  local previous="$_ds_prompt_context:$_ds_prompt_git:$_ds_prompt_path:$_ds_prompt_mr"
  local -a values
  if [[ $2 != (err|nval) ]] && IFS= read -r -u "$fd" line; then
    values=("${(@ps:\t:)line}")
    values=("${(@Q)values}")
  fi
  zle -F "$fd"
  exec {fd}<&-
  _ds_prompt_async_fd=''
  # Commands invalidate snapshots still in flight.
  if (( _ds_prompt_pending_generation != _ds_prompt_generation )); then
    _ds_prompt_async
    return 0
  fi
  (( $#values == 13 )) || return 0
  _ds_prompt_context=$values[1]
  _ds_prompt_git=$values[2]
  _ds_prompt_path=$values[3]
  _ds_prompt_root=$values[4]
  _ds_prompt_pwd=$values[5]
  _ds_prompt_branch=$values[6]
  _ds_prompt_root_branch=$values[7]
  _ds_prompt_physical=$values[8]
  _ds_prompt_oid=$values[9]
  _ds_prompt_subject=$values[10]
  _ds_prompt_command=$values[11]
  _ds_prompt_apple_git=$values[12]
  _ds_prompt_apple_key=$values[13]
  _ds_prompt_mr
  if [[ $previous != "$_ds_prompt_context:$_ds_prompt_git:$_ds_prompt_path:$_ds_prompt_mr" ]]; then
    zle && zle reset-prompt
  fi
  return 0
}

_ds_prompt_async() {
  emulate -L zsh
  [[ -z $_ds_prompt_async_fd ]] || return 0
  local fd
  _ds_prompt_pending_generation=$_ds_prompt_generation
  exec {fd}< <(_ds_prompt_snapshot </dev/null 2>/dev/null)
  _ds_prompt_async_fd=$fd
  zle -F "$fd" _ds_prompt_async_ready
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
  if [[ -o interactive && -o zle ]]; then
    _ds_prompt_cache_location
    local key="${(q)_ds_prompt_cache_file}:$_ds_prompt_cache_key:${(q)PATH}:${(q)DEVELOPER_DIR}:${(q)SDKROOT}:${(q)TOOLCHAINS}"
    if [[ $key != $_ds_prompt_async_key ]]; then
      _ds_prompt_context='' _ds_prompt_git='' _ds_prompt_root='' _ds_prompt_branch=''
      _ds_prompt_mr=''
      _ds_prompt_path='%F{cyan}%(5~|…/%4~|%~)%f'
      _ds_prompt_cache_read
      _ds_prompt_async_key=$key
    fi
    _ds_prompt_mr_key=''
    (( ++_ds_prompt_generation ))
    _ds_prompt_async
  else
    _ds_prompt_context
    _ds_prompt_git
    _ds_prompt_path
    _ds_prompt_mr
  fi
  return 0
}

add-zsh-hook preexec _ds_prompt_preexec
add-zsh-hook precmd _ds_prompt_precmd
