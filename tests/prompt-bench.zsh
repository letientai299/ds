#!/bin/zsh -df
setopt err_exit pipe_fail
root=${0:A:h:h}
mkdir -p "$root/.ai/prompt"
work=$(mktemp -d "$root/.ai/prompt/bench.XXXXXX")
trap 'cd "$root"; rm -rf "$work"' EXIT
export GIT_CEILING_DIRECTORIES=${work:h}
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
source "$root/src/dotfiles/prompt.zsh"
preexec_functions=()
COLUMNS=160
samples=${DS_BENCH_SAMPLES:-100}
[[ $samples == <1-> ]] || { print -ru2 'samples must be positive'; exit 1; }
print 'case,sample,milliseconds' > "$root/.ai/prompt/samples.csv"
bench() {
  local label=$1 mode=${2:-warm} rendered
  local -F start elapsed
  local -a timings=()
  repeat 5; do _ds_prompt_precmd; done
  repeat $samples; do
    [[ $mode != cold ]] || _ds_prompt_oid=''
    start=$EPOCHREALTIME
    if [[ $mode == baseline ]]; then
      rendered=${(%%)baseline}
    else
      _ds_prompt_precmd
      rendered=${(%%)PROMPT}
    fi
    elapsed=$(( (EPOCHREALTIME - start) * 1000 ))
    timings+=($elapsed)
    print -r -- "$label,$#timings,$elapsed" >> "$root/.ai/prompt/samples.csv"
  done
  timings=(${(on)timings})
  printf '%-24s p50=%8.3fms p95=%8.3fms max=%8.3fms n=%d\n' \
    "$label" "$timings[$(( (samples + 1) / 2 ))]" "$timings[$(( (samples * 95 + 99) / 100 ))]" "$timings[-1]" "$samples"
}
print -r -- "zsh=$ZSH_VERSION git=$(git --version) os=$(uname -sm)"
cd "$work"
baseline='%F{cyan}%n@%m%f %F{blue}%~%f
%(?.%F{green}.%F{red})❯%f '
bench baseline baseline
bench outside
mkdir small
git init -qb main small
cd small
print initial > tracked
git add tracked
git commit -qm initial
bench small-clean
bench small-new-head cold
print dirty >> tracked
print new > untracked
bench small-dirty
cd "$work"
git init -qb main large
cd large
for i in {1..10000}; do print file > "tracked-$i"; done
git add -- tracked-*
git commit -qm 'ten thousand files'
bench large-clean
for i in {1..100}; do print dirty >> "tracked-$i"; done
for i in {1..1000}; do print new > "untracked-$i"; done
bench large-dirty
cd "$root"
bench ds-checkout
