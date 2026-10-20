#!/bin/zsh -df
setopt err_exit pipe_fail extended_glob
root=${0:A:h:h}
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-prompt-async.XXXXXX")
zmodload zsh/datetime
zmodload zsh/zpty
zmodload zsh/zselect
trap 'zpty -d 2>/dev/null; cd "$root"; rm -rf "$work"' EXIT
export DS_PROMPT_SOURCE="$root/assets/dotfiles/prompt.zsh" DS_ASYNC_STATE="$work/state"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export XDG_CACHE_HOME="$work/cache"
export DS_ASYNC_GIT=${commands[git]}
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
mkdir "$work/bin"
cat > "$work/bin/git" <<'GIT'
#!/bin/sh
printf '%s\n' "$1" >> "$DS_ASYNC_STATE.calls"
exec "$DS_ASYNC_GIT" "$@"
GIT
print -r -- $'#!/bin/sh\nprintf "17 https://gitlab.example/repo/-/merge_requests/17\\n"' > "$work/bin/glab"
chmod +x "$work/bin/git" "$work/bin/glab"
export PATH="$work/bin:$PATH"
for repo in first second; do
  git init -qb "$repo" "$work/$repo"
  git -C "$work/$repo" -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m "$repo subject"
done
cd "$work/first"
(
  source "$DS_PROMPT_SOURCE"
  for order in parent-first child-first; do
    XDG_CACHE_HOME="$work/layout-cache/$order"
    directories=("$work/layout/$order" "$work/layout/$order/entry")
    mkdir -p "$directories[2]"
    [[ $order != child-first ]] || directories=("$directories[2]" "$directories[1]")
    for directory in "${directories[@]}" /; do
      cd "$directory"
      _ds_prompt_cache_location
      _ds_prompt_git=$PWD
      _ds_prompt_cache_write
    done
    for directory in "${directories[@]}" /; do
      cd "$directory"
      _ds_prompt_cache_location
      _ds_prompt_git=''
      _ds_prompt_cache_read
      [[ $_ds_prompt_git == $PWD ]] || { print -ru2 'cache directory collision'; exit 1; }
    done
    cd "$directories[1]"
    _ds_prompt_cache_location
    legacy="$XDG_CACHE_HOME/ds/prompt-v1/$EUID${PWD}/entry"
    mkdir -p "${legacy:h}"
    cp "$_ds_prompt_cache_file" "$legacy"
    rm "$_ds_prompt_cache_file"
    _ds_prompt_git=''
    _ds_prompt_cache_read
    [[ $_ds_prompt_git == $PWD ]] || { print -ru2 'legacy cache lost'; exit 1; }
    _ds_prompt_cache_write
    [[ -f $_ds_prompt_cache_file ]] || { print -ru2 'cache migration failed'; exit 1; }
    rm "$_ds_prompt_cache_file"
    mkdir "$_ds_prompt_cache_file"
    _ds_prompt_cache_write
    contents=("$_ds_prompt_cache_file"/*(ND))
    (( $#contents == 0 )) || { print -ru2 'cache directory contains temporary files'; exit 1; }
  done
)
print -n > "$DS_ASYNC_STATE.calls"
cat > "$work/init" <<'INIT'
zmodload zsh/zselect
source "$DS_PROMPT_SOURCE"
typeset -gi reset_count=0
zle() {
  [[ $1 != reset-prompt ]] || (( ++reset_count ))
  builtin zle "$@"
}
functions[original_snapshot]=$functions[_ds_prompt_snapshot]
_ds_prompt_snapshot() {
  print started >> "$DS_ASYNC_STATE.workers"
  zselect -t 40 || true
  original_snapshot
}
probe() {
  print -r -- "$_ds_prompt_git" > "$DS_ASYNC_STATE.git"
  print -r -- "$_ds_prompt_status" > "$DS_ASYNC_STATE.status"
  print -r -- "$_ds_prompt_root" > "$DS_ASYNC_STATE.root"
  print -r -- "$_ds_prompt_path" > "$DS_ASYNC_STATE.path"
  print -r -- "$_ds_prompt_cache_file" > "$DS_ASYNC_STATE.cachefile"
  print -r -- "$_ds_prompt_cache_key" > "$DS_ASYNC_STATE.cachekey"
  print -r -- "${(%%)PROMPT}" > "$DS_ASYNC_STATE.prompt"
}
watch_ready() {
  functions[original_ready]=$functions[_ds_prompt_async_ready]
  _ds_prompt_async_ready() {
    local -i before=$reset_count
    original_ready "$@"
    if [[ -z $_ds_prompt_async_fd ]]; then
      probe
      print $(( reset_count - before )) > "$DS_ASYNC_STATE.resets"
      print ready > "$DS_ASYNC_STATE.ready"
    fi
  }
}
watch_ready
add-zsh-hook precmd probe
COLUMNS=160
INIT
fail() { print -ru2 -- "prompt async: $*"; exit 1; }
drain() {
  local output
  while zpty -r shell output; do
    print -r -- "$output" >> "$work/terminal.log"
  done
}
await_file() {
  repeat 500; do
    drain
    [[ -f $1 ]] && return 0
    zselect -t 1 || true
  done
  fail "timeout: $1"
}
run() {
  rm -f "$DS_ASYNC_STATE.prompt" "$DS_ASYNC_STATE.ready"
  zpty -wn shell "$1"$'\n'
  await_file "$DS_ASYNC_STATE.prompt"
}
await_ready() { await_file "$DS_ASYNC_STATE.ready"; }
zpty -b shell 'trap - EXIT; exec zsh -df'
start=$EPOCHREALTIME
run "source ${(q)work}/init"
(( EPOCHREALTIME - start < 0.3 )) || fail 'first prompt blocked'
[[ -z $(<"$DS_ASYNC_STATE.git") ]] || fail 'uncached Git visible'
[[ $(<"$DS_ASYNC_STATE.prompt") != *•* ]] || fail 'worker counted as job'
await_ready
[[ $(<"$DS_ASYNC_STATE.git") == *'first subject%f %F{242}'* ]] || fail 'first result missing'
[[ $(<"$DS_ASYNC_STATE.calls") == $'status\nlog' ]] || fail 'cold Git calls'
# Cached text stays visible during refresh.
print -n > "$DS_ASYNC_STATE.calls"
start=$EPOCHREALTIME
run ':'
(( EPOCHREALTIME - start < 0.3 )) || fail 'warm prompt blocked'
[[ $(<"$DS_ASYNC_STATE.git") == *'first subject'* ]] || fail 'warm cache lost'
zpty -wn shell "print -r -- buffer-kept > ${(q)DS_ASYNC_STATE}.buffer"
await_ready
[[ $(<"$DS_ASYNC_STATE.calls") == status ]] || fail 'HEAD cache lost'
rm -f "$DS_ASYNC_STATE.prompt" "$DS_ASYNC_STATE.ready"
zpty -wn shell $'\n'
await_file "$DS_ASYNC_STATE.buffer"
[[ $(<"$DS_ASYNC_STATE.buffer") == buffer-kept ]] || fail 'redraw changed input'
await_file "$DS_ASYNC_STATE.prompt"
await_ready
run '(exit 23)'
[[ $(<"$DS_ASYNC_STATE.status") == ' %F{red}[23]%f' ]] || fail 'exit code missing'
await_ready
[[ $(<"$DS_ASYNC_STATE.status") == ' %F{red}[23]%f' ]] || fail 'callback changed exit code'
# Empty Enter also triggers a fresh snapshot.
run ''
await_ready
[[ $(<"$DS_ASYNC_STATE.status") == ' %F{red}[23]%f' ]] || fail 'empty Enter status'
# New shells show cached text before Git.
cachefile=$(<"$DS_ASYNC_STATE.cachefile")
[[ -f $cachefile ]] || fail 'persistent cache missing'
zpty -d shell
zpty -b shell 'trap - EXIT; exec zsh -df'
print -n > "$DS_ASYNC_STATE.calls"
start=$EPOCHREALTIME
run "source ${(q)work}/init"
(( EPOCHREALTIME - start < 0.3 )) || fail 'cached startup blocked'
[[ $(<"$DS_ASYNC_STATE.git") == *'first subject'* ]] || fail 'startup cache missing'
[[ $(<"$DS_ASYNC_STATE.path") == '%B%F{blue}first%b%F{cyan}%f' ]] || fail 'startup path flashed'
[[ -z $(<"$DS_ASYNC_STATE.status") && ! -s $DS_ASYNC_STATE.calls ]] || fail 'cached startup ran Git'
await_ready
[[ $(<"$DS_ASYNC_STATE.resets") == 0 ]] || fail 'unchanged cache redrawn'
# Environment changes must update cache identity.
previous_key=$(<"$DS_ASYNC_STATE.cachekey")
run 'saved_alias=${LC_SSH_ALIAS-}; saved_connection=${SSH_CONNECTION-}; SSH_CONNECTION=test; LC_SSH_ALIAS=cache-review'
await_ready
[[ $(<"$DS_ASYNC_STATE.cachekey") != $previous_key ]] || fail 'SSH cache identity stale'
run 'LC_SSH_ALIAS=$saved_alias; SSH_CONNECTION=$saved_connection'
await_ready
previous_file=$(<"$DS_ASYNC_STATE.cachefile")
run 'saved_cache=$XDG_CACHE_HOME; XDG_CACHE_HOME=$saved_cache/changed'
await_ready
[[ $(<"$DS_ASYNC_STATE.cachefile") != $previous_file ]] || fail 'cache location stale'
run 'XDG_CACHE_HOME=$saved_cache'
await_ready
# Coalesce prompts without applying stale results.
print -n > "$DS_ASYNC_STATE.workers"
run ':'
run "cd ${(q)work}/second"
[[ -z $(<"$DS_ASYNC_STATE.git") ]] || fail 'old directory Git visible'
await_ready
[[ $(<"$DS_ASYNC_STATE.git") == *'second subject'* ]] || fail 'stale directory result'
[[ $(<"$DS_ASYNC_STATE.root") == "${work:A}/second" ]] || fail 'stale root'
worker_log=$(<"$DS_ASYNC_STATE.workers")
workers=("${(@f)worker_log}")
(( $#workers <= 2 )) || fail 'duplicate workers'
run 'git checkout -qb third; git -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m '\''literal %F{red} $(touch INJECTED) `touch ALSO`'\'
await_ready
[[ $(<"$DS_ASYNC_STATE.git") == *'⑂ third'*'literal %%F{red}'* ]] || fail 'branch result missing'
[[ ! -e $work/second/INJECTED && ! -e $work/second/ALSO ]] || fail 'snapshot injection'
# Preserve whitespace, quotes, and empty values.
run 'mkdir -p $'\''odd\n\tname'\''; cd $'\''odd\n\tname'\'
await_ready
[[ $(<"$DS_ASYNC_STATE.root") == "${work:A}/second" ]] || fail 'quoted payload corrupted'
# Fetch MRs after Git settles.
repeat 300; do
  drain
  [[ $(<"$work/terminal.log") == *'!17'* ]] && break
  zselect -t 1 || true
done
[[ $(<"$work/terminal.log") == *'!17'* ]] || fail 'MR lookup missing'
run 'local_path=$PATH; PATH=/missing'
await_ready
[[ -z $(<"$DS_ASYNC_STATE.git") ]] || fail 'missing Git retained'
run 'PATH=$local_path'
await_ready
[[ $(<"$DS_ASYNC_STATE.git") == *'⑂ third'* ]] || fail 'PATH recovery failed'
# Failed workers release descriptors and retry.
run 'functions[saved_snapshot]=$functions[_ds_prompt_snapshot]; _ds_prompt_snapshot() { return 1; }'
await_ready
run 'functions[_ds_prompt_snapshot]=$functions[saved_snapshot]'
await_ready
[[ $(<"$DS_ASYNC_STATE.git") == *'⑂ third'* ]] || fail 'worker recovery failed'
# Reload keeps the pending descriptor registered.
run ':'
run 'source "$DS_PROMPT_SOURCE"; watch_ready'
await_ready
[[ $(<"$DS_ASYNC_STATE.git") == *'⑂ third'* ]] || fail 'reload result missing'
run 'cd /'
await_ready
[[ -z $(<"$DS_ASYNC_STATE.git") ]] || fail 'outside Git retained'
run 'print -r -- "$_ds_prompt_async_fd ${#_ds_prompt_mr_fds}" > "$DS_ASYNC_STATE.fds"'
await_ready
# Inspect descriptors before starting another worker.
[[ $(<"$DS_ASYNC_STATE.fds") == ' 0' ]] || fail 'descriptors leaked'
# Corrupt caches fall back without blocking.
zpty -d shell
print -r -- garbage > "$cachefile"
zpty -b shell 'trap - EXIT; exec zsh -df'
run "source ${(q)work}/init"
[[ -z $(<"$DS_ASYNC_STATE.git") ]] || fail 'corrupt cache accepted'
await_ready
zpty -d shell
rm "$cachefile"
mkfifo "$cachefile"
zpty -b shell 'trap - EXIT; exec zsh -df'
start=$EPOCHREALTIME
run "source ${(q)work}/init"
(( EPOCHREALTIME - start < 0.3 )) || fail 'FIFO cache blocked startup'
await_ready
[[ -f $cachefile ]] || fail 'FIFO cache not replaced'
zpty -d shell
git -C "$work/first" -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m refreshed
zpty -b shell 'trap - EXIT; exec zsh -df'
run "source ${(q)work}/init"
[[ $(<"$DS_ASYNC_STATE.git") == *'first subject'* ]] || fail 'stale cache not reused'
await_ready
[[ $(<"$DS_ASYNC_STATE.git") == *'refreshed'* ]] || fail 'stale cache not refreshed'
print 'prompt async: ok'
