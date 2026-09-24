#!/bin/zsh -df
setopt err_exit pipe_fail extended_glob
root=${0:A:h:h}
mkdir -p "$root/.ai/prompt"
work=$(mktemp -d "$root/.ai/prompt/test.XXXXXX")
trap 'cd "$root"; rm -rf "$work"' EXIT
export GIT_CEILING_DIRECTORIES=${work:h}
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
source "$root/src/dotfiles/prompt.zsh"
COLUMNS=160
fail() { print -ru2 -- "prompt: $*"; exit 1; }
expect() {
  _ds_prompt_git
  [[ $_ds_prompt_git == ${~1} ]] || fail "$2: $_ds_prompt_git"
}
cd "$work"
expect '' 'outside repository'
git init -qb main repo
cd repo
expect '*⑂ main%f' unborn
print initial > tracked
git add tracked
git commit -qm initial
expect '*⑂ main%f *initial%f' clean
print changed >> tracked
expect '* !1*' unstaged
git add tracked
expect '* +1*' staged
print more >> tracked
print unknown > $'odd\nname'
expect '* +1 !1 ?1*' mixed
git stash push -qu
expect '* ≡1*' stash
git mv tracked renamed
expect '* +1*' rename
git commit -qm rename
rm renamed
expect '* !1*' deletion
git restore renamed
git checkout -q --detach
expect '*⑂ @????????%f*' detached
git checkout -q main
git branch upstream
git branch --set-upstream-to=upstream >/dev/null
git commit -q --allow-empty -m ahead
expect '* ↑1*' ahead
git checkout -q upstream
print upstream > renamed
git commit -qam upstream
git checkout -q main
expect '* ↑1 ↓1*' diverged
git config status.aheadBehind false
expect '* ↑1 ↓1*' 'ahead config override'
print local > renamed
git commit -qam local
git merge upstream >/dev/null 2>&1 && fail 'merge should conflict'
expect '* ×1*' conflict
git merge --abort
git worktree add -qb linked "$work/linked" >/dev/null 2>&1
cd "$work/linked"
expect '*⑂ linked%f*local%f' worktree
cd "$work/repo"
git -c protocol.file.allow=always submodule add -q "$work/linked" sub
git commit -qm submodule
print dirty >> sub/renamed
expect '* !1*' 'modified submodule'
git -C sub restore renamed
print unknown > sub/unknown
expect '* !1*' 'untracked submodule'
rm sub/unknown
git -C sub -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m subhead
expect '* !1*' 'changed submodule head'
git submodule update -q
git submodule deinit -q -f sub
git checkout -q upstream
expect '*⑂ upstream%f*upstream%f' 'commit cache invalidation'
git checkout -qb 'literal%F{red}$(false)'
git commit -q --allow-empty -m $'literal %F{red} $(touch INJECTED) `touch ALSO` \033[31m'
_ds_prompt_git
[[ $_ds_prompt_git == *'literal%%F{red}$(false)'*'literal %%F{red}'* ]] || fail escaping
rendered=${(%%)PROMPT}
[[ ! -e INJECTED && ! -e ALSO && $rendered == *'$(touch INJECTED)'* ]] || fail 'prompt injection'
[[ $_ds_prompt_subject != *$'\033'* ]] || fail 'terminal injection'
cd "$work"
git init -q --bare bare
cd bare
expect '' bare
local_path=$PATH
PATH=/missing
expect '' 'missing git'
PATH=$local_path
cd "$work/repo"
source "$root/src/dotfiles/prompt.zsh"
[[ ${(M)#precmd_functions:#_ds_prompt_precmd} == 1 ]] || fail 'duplicate hook'
preexec_functions=()
if () { return 42; }; then
  fail "expected failure"
else
  _ds_prompt_precmd
fi
[[ $_ds_prompt_char == '%F{red}[42]❯' ]] || fail 'exit code'
_ds_prompt_started=$(( EPOCHREALTIME - 9 ))
_ds_prompt_precmd
[[ -z $_ds_prompt_duration ]] || fail 'short duration'
_ds_prompt_started=$(( EPOCHREALTIME - 65 ))
_ds_prompt_precmd
[[ $_ds_prompt_duration == '%F{yellow}1m5s%f ' ]] || fail 'long duration'
_ds_prompt_precmd
[[ -z $_ds_prompt_duration ]] || fail 'idle duration'
COLUMNS=40
rendered=${(%%)PROMPT}
plain=${rendered//$'\e'\[[0-9\;]##m/}
lines=("${(@f)plain}")
[[ $#lines == 2 && ${#lines[1]} -le 39 ]] || fail 'terminal width'
[[ $lines[2] == [0-9][0-9]:[0-9][0-9]:[0-9][0-9]' ❯ ' ]] || fail clock
COLUMNS=160

zmodload zsh/zpty
zmodload zsh/zselect
export DS_PROMPT_SOURCE="$root/src/dotfiles/prompt.zsh" DS_PROMPT_PROBE="$work/probe"
cat > "$work/init" <<'INIT'
source "$DS_PROMPT_SOURCE"
probe() { print -r -- "${(%%)PROMPT}" > "$DS_PROMPT_PROBE"; }
add-zsh-hook precmd probe
INIT
zpty -b shell zsh -df
trap 'zpty -d shell; cd "$root"; rm -rf "$work"' EXIT
await_prompt() {
  local output
  repeat 2000; do
    while zpty -r shell output; do print -r -- "$output" >> "$root/.ai/prompt/terminal.log"; done
    [[ -s $work/probe ]] && return 0
    zselect -t 1 || true
  done
  fail 'interactive prompt timeout'
}
run() {
  rm -f "$work/probe"
  print -r -- "RUN: $1" >> "$root/.ai/prompt/terminal.log"
  zpty -w shell "$1"
  await_prompt
}
run "source ${(q)work}/init"
[[ $(<"$work/probe") != *•* ]] || fail 'zero jobs'
run 'sleep 60 & first=$!'
[[ $(<"$work/probe") == *'• '* && $(<"$work/probe") != *'1• '* ]] || fail 'one job'
run 'sleep 60 | cat & second=$!'
[[ $(<"$work/probe") == *'2• '* ]] || fail 'pipeline job count'
run 'kill -STOP $first; sleep 0.05'
[[ $(<"$work/probe") == *'2• '* ]] || fail 'stopped job count'
run 'kill -CONT $first; kill $first; wait $first 2>/dev/null; :'
[[ $(<"$work/probe") == *'• '* && $(<"$work/probe") != *'2• '* ]] || fail 'completed job count'
run 'kill %2; wait 2>/dev/null; :'
[[ $(<"$work/probe") != *•* ]] || fail 'jobs cleared'
run 'sleep 0.1 &'
[[ $(<"$work/probe") == *'• '* ]] || fail 'short background job'
run 'sleep 0.2'
[[ $(<"$work/probe") != *•* ]] || fail 'finished background job'
run 'setopt pipe_fail; false | true'
[[ $(<"$work/probe") == *'[1]❯'* ]] || fail 'pipeline failure'
run '(exit 23)'
[[ $(<"$work/probe") == *$'\e[31m[23]❯'* ]] || fail 'interactive failure color'
run ':'
[[ $(<"$work/probe") == *$'\e[32m❯'* ]] || fail 'interactive success color'
run 'sleep 10.1'
[[ $(<"$work/probe") == *'10s'* ]] || fail 'interactive wall time'
run ':'
[[ $(<"$work/probe") != *'10s'* ]] || fail 'wall time reset'
print 'prompt: ok'
