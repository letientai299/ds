#!/bin/zsh -df
setopt err_exit pipe_fail extended_glob
root=${0:A:h:h}
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-prompt-mr.XXXXXX")
zmodload zsh/datetime
zmodload zsh/zpty
zmodload zsh/zselect
trap 'zpty -d 2>/dev/null; cd "$root"; rm -rf "$work"' EXIT
export XDG_CACHE_HOME="$work/cache" DS_MR_CALLS="$work/calls"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export DS_PROMPT_SOURCE="$root/assets/dotfiles/prompt.zsh" DS_MR_PROBE="$work/probe"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
mkdir "$work/bin"
cat > "$work/bin/glab" <<'GLAB'
#!/bin/sh
printf '%s\n' "$4" >> "$DS_MR_CALLS"
sleep 0.5
for arg do
  if [ "$arg" = --all ]; then
    printf '%s\n' '99 https://gitlab.example/test/repo/-/merge_requests/99'
    exit 0
  fi
done
case "$4" in
  main) printf '%s\n' '17 https://gitlab.example/test/repo/-/merge_requests/17' ;;
  second) printf '%s\n' '23 https://gitlab.example/test/repo/-/merge_requests/23' ;;
  none|merged|closed) printf '%s\n' '0' ;;
  fail) exit 1 ;;
  *) printf '99 https://gitlab.example/\033[31m' ;;
esac
GLAB
chmod +x "$work/bin/glab"
export PATH="$work/bin:$PATH"
git init -qb main "$work/repo"
cd "$work/repo"
git -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m initial
legacy="$XDG_CACHE_HOME/ds/prompt-mr${PWD:A}/branches/main/entry"
mkdir -p "${legacy:h}"
print "$(( EPOCHSECONDS + 86400 )) 99 https://gitlab.example/test/repo/-/merge_requests/99" > "$legacy"
cat > "$work/init" <<'INIT'
source "$DS_PROMPT_SOURCE"
# Exercise MR callbacks separately.
_ds_prompt_async() {
  _ds_prompt_context
  _ds_prompt_git
  _ds_prompt_path
  _ds_prompt_mr
}
functions[git_sync]=$functions[_ds_prompt_async]
COLUMNS=160
probe() { print -r -- "$_ds_prompt_mr" > "$DS_MR_PROBE"; }
add-zsh-hook precmd probe
INIT
fail() { print -ru2 -- "prompt MR: $*"; exit 1; }
local output terminal=''
read_calls() {
  local log=$(<"$DS_MR_CALLS")
  calls=("${(@f)log}")
}
drain() {
  while zpty -r shell output; do terminal+=$output; done
}
await_text() {
  local pattern=$1
  repeat 300; do
    drain
    [[ $terminal == *"$pattern"* ]] && return 0
    zselect -t 1 || true
  done
  fail "missing $pattern"
}
run() {
  rm -f "$work/probe"
  terminal=''
  zpty -w shell "$1"
  repeat 300; do
    drain
    [[ -f $work/probe ]] && return 0
    zselect -t 1 || true
  done
  fail "prompt timeout: $1; $terminal"
}
zpty -b shell 'trap - EXIT; exec zsh -df'
start=$EPOCHREALTIME
run "source ${(q)work}/init"
(( EPOCHREALTIME - start < 0.4 )) || fail 'lookup blocked prompt'
[[ -z $(<"$work/probe") ]] || fail 'uncached MR visible'
[[ $terminal != *•* ]] || fail 'lookup counted as job'
run ':'
await_text '!17'
[[ $terminal == *$'\e]8;;https://gitlab.example/test/repo/-/merge_requests/17\e\\'* ]] || fail 'hyperlink missing'
run ':'
[[ $(<"$work/probe") == *'!17'* ]] || fail 'warm cache missing'
[[ $(<"$work/calls") == main ]] || fail 'duplicate lookup'
cachefile="$XDG_CACHE_HOME/ds/prompt-mr-open${PWD:A}/branches/main/entry"
read -r expiry result < "$cachefile"
(( expiry <= EPOCHSECONDS + 60 )) || fail 'active MR cache too long'
run 'print -r -- ${#_ds_prompt_mr_fds} ${#_ds_prompt_mr_pending} > "$XDG_CACHE_HOME/fds"'
[[ $(<"$XDG_CACHE_HOME/fds") == '0 0' ]] || fail 'descriptor state leaked'
# Pending results must follow their branch.
run 'git checkout -qb second'
run 'git checkout -q main'
await_text '!17'
zselect -t 70 || true
run ':'
[[ $(<"$work/probe") == *'!17'* && $(<"$work/probe") != *'!23'* ]] || fail 'stale response'
run 'git checkout -q second'
[[ $(<"$work/probe") == *'!23'* ]] || fail 'branch cache missing'
run 'COLUMNS=20; :'
await_text $'\e]8;;\e\\'
run 'COLUMNS=160; :'
run 'setopt prompt_bang; source "$DS_PROMPT_SOURCE"; functions[_ds_prompt_async]=$functions[git_sync]'
[[ $(<"$work/probe") == *'!23'* ]] || fail 'reload cache missing'
zpty -d shell
zpty -b shell 'trap - EXIT; exec zsh -df'
run "source ${(q)work}/init"
await_text '!23'
run ':'
[[ $(<"$work/probe") == *'!23'* ]] || fail 'persistent cache missing'
[[ $(<"$work/calls") == $'main\nsecond' ]] || fail 'persistent cache refetched'
for branch in none merged closed fail unsafe; do
  run "git checkout -qb $branch"
  zselect -t 70 || true
  run ':'
  [[ -z $(<"$work/probe") ]] || fail "$branch result visible"
  run ':'
  read_calls
  [[ ${(M)#calls:#$branch} == 1 ]] || fail "$branch repeated lookup"
done
run 'git checkout -q --detach 2>/dev/null; :'
[[ -z $(<"$work/probe") ]] || fail 'detached MR visible'
run 'git checkout -q main'
mkdir "$work/git-only"
source "$DS_PROMPT_SOURCE"
_ds_prompt_resolve_git
ln -s "${commands[$_ds_prompt_command]:-$_ds_prompt_command}" "$work/git-only/git"
run "local_path=\$PATH; PATH=${(q)work}/git-only"
[[ -z $(<"$work/probe") ]] || fail 'missing glab MR visible'
run 'print -r -- "$_ds_prompt_root|$_ds_prompt_git" > "$XDG_CACHE_HOME/fallback"'
[[ $(<"$XDG_CACHE_HOME/fallback") == *'/repo|'*'⑂ main'* ]] || fail 'missing glab Git lost'
run 'PATH=$local_path; :'
[[ $(<"$work/probe") == *'!17'* ]] || fail 'glab recovery missing'
run 'local_path=$PATH; PATH=/missing'
[[ -z $(<"$work/probe") ]] || fail 'missing tools MR visible'
run 'PATH=$local_path; :'
[[ $(<"$work/probe") == *'!17'* ]] || fail 'tools recovery missing'
run 'print "0" > "$_ds_prompt_mr_key"; _ds_prompt_mr_expiry[$_ds_prompt_mr_key]=0; :'
zselect -t 70 || true
run ':'
read_calls
[[ ${(M)#calls:#main} == 2 ]] || fail 'expired cache not refreshed'
# Slow cache reads must remain asynchronous.
run 'print -r -- "$_ds_prompt_mr_key" > "$XDG_CACHE_HOME/key"'
cachefile=$(<"$XDG_CACHE_HOME/key")
rm "$cachefile"
mkfifo "$cachefile"
(
  trap - EXIT
  sleep 0.5
  print "$(( EPOCHSECONDS + 86400 )) 17 https://gitlab.example/test/repo/-/merge_requests/17" > "$cachefile"
) &
writer=$!
start=$EPOCHREALTIME
run '_ds_prompt_mr_expiry[$_ds_prompt_mr_key]=0; :'
(( EPOCHREALTIME - start < 0.4 )) || fail 'cache blocked prompt'
[[ -z $(<"$work/probe") ]] || fail 'pending cache MR visible'
await_text '!17'
wait "$writer"
# URL bytes cannot inject prompt controls.
source "$DS_PROMPT_SOURCE"
_ds_prompt_mr_key=test
_ds_prompt_mr_values[test]='31 https://gitlab.example/100%25'
_ds_prompt_mr_render
[[ $_ds_prompt_mr == *'100%%25'* ]] || fail 'URL percent escaping'
COLUMNS=160
_ds_prompt_context='context '
_ds_prompt_path='path'
_ds_prompt_git=' git'
rendered=${(%%)PROMPT}
[[ $rendered == $'\n\e[32m\e]8;;https://gitlab.example/100%25\e\\!31\e]8;;\e\\\e[39m context path git'* ]] || fail 'MR position'

_ds_prompt_mr_values[test]=$'31 https://gitlab.example/\e[31m'
_ds_prompt_mr_render
[[ -z $_ds_prompt_mr ]] || fail 'URL control injection'
print 'prompt MR: ok'
