zmodload zsh/zpty
zmodload zsh/zselect

function fail() {
  print -ru2 -- "plugins: $*"
  [[ ! -r $HOME/probe ]] || cat "$HOME/probe" >&2
  [[ ! -r $HOME/terminal ]] || cat "$HOME/terminal" >&2
  exit 1
}

function await_file() {
  local output
  repeat 600; do
    while zpty -r shell output; do
      print -r -- "$output" >>"$HOME/terminal"
    done
    [[ -f $1 ]] && return 0
    zpty -t shell || fail 'shell exited early'
    zselect -t 5
  done
  fail "timeout: ${1:t}"
}

function expect_probe() {
  repeat 100; do
    rm -f "$HOME/probe"
    zpty -w -n shell $'\x18\x14'
    await_file "$HOME/probe"
    [[ $(<"$HOME/probe") == ${~1} ]] && return 0
    zselect -t 5
  done
  fail "$2"
}

cat >"$HOME/.zshrc" <<'ZSH'
if [[ $DS_TEST_MODE == existing ]]; then
  autoload -Uz compinit
  compinit -D -i
  function compinit() { print duplicate >"$HOME/duplicate"; }
fi
export DS_SHELL_ROOT="${DS_TEST_SHELL:A:h:h:h}"
source "$DS_TEST_SHELL"
function reload() { source "$DS_TEST_SHELL"; }
reload
PROMPT='plugins> '
function first_prompt() {
  print -r -- "$+functions[_zsh_autosuggest_start] $+functions[_zsh_highlight] $+functions[enable-fzf-tab] ${+_ds_fzf_loaded} ${+_ds_zoxide_loaded} ${+DS_TEST_MISE_READY}" >"$HOME/first"
  precmd_functions=(${precmd_functions:#first_prompt})
}
precmd_functions+=(first_prompt)
function _ds_test_probe() {
  print -r -- "$BUFFER|$POSTDISPLAY|${(j:,:)region_highlight}" >"$HOME/probe"
}
function _ds_test_ready() {
  [[ ${_ds_test_waiting:-0} == 1 ]] && print ready >"$HOME/prompt-ready"
  return 0
}
autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-init _ds_test_ready
zle -N _ds_test_probe
bindkey '^X^T' _ds_test_probe
bindkey '^X^F' autosuggest-fetch
print -r -- $#_zsh_defer_tasks >"$HOME/queued"
zsh-defer -dm +1 +2 -c 'print ready >"$HOME/ready"'
ZSH

zpty -b shell zsh -d
trap 'zpty -d shell' EXIT
zpty -w shell 'print early >"$HOME/early"'
await_file "$HOME/ready"
[[ $(<"$HOME/early") == early ]] || fail 'early input lost'
[[ $(<"$HOME/first") == '0 0 0 0 0 0' ]] || fail 'plugins blocked first prompt'
[[ $(<"$HOME/queued") == 6 ]] || fail 'reload duplicated queue'
[[ ! -e $HOME/duplicate ]] || fail 'completion initialized twice'

zpty -w shell 'print -r -- "$_ds_plugins_ready|$_comps[ds]|$+functions[enable-fzf-tab]|$+functions[_zsh_autosuggest_start]|$+functions[_zsh_highlight]|${+_ds_fzf_loaded}|$+functions[zoxide-ready]|$DS_TEST_MISE_READY|$ZSH_HIGHLIGHT_STYLES[comment]" >"$HOME/check"'
await_file "$HOME/check"
[[ $(<"$HOME/check") == '1|_ds_complete|1|1|1|1|1|1|standout' ]] || fail "plugin state: $(<"$HOME/check")"
zpty -w shell '[[ $_comps[cmake] == _cmake && ${fpath[(Ie)$HOME/.local/share/zsh/site-functions]} -gt 0 && ${#fpath} == ${#${(u)fpath}} ]] && print ready >"$HOME/completions"'
await_file "$HOME/completions"
zpty -w shell 'before="$(bindkey "^I")"; reload; [[ $(bindkey "^I") == "$before" && $before == *fzf-tab-complete* && $#_zsh_defer_tasks == 0 ]] && print ready >"$HOME/reload"'
await_file "$HOME/reload"

zpty -w -n shell $'\x15cd ~/casecho\t'
expect_probe 'cd ~/CaseChoice/||*' 'case-insensitive completion failed'
zpty -w -n shell $'\x15'
zpty -w -n shell $'cd ~/CaseChce\x02\x02\t'
expect_probe 'cd ~/CaseChoice/||*' 'midword completion failed'
zpty -w -n shell $'\x15'

zpty -w shell '_ds_test_waiting=1'
await_file "$HOME/prompt-ready"
rm -f "$HOME/prompt-ready"
zpty -w shell 'echo ds-history-expansion'
await_file "$HOME/prompt-ready"
rm -f "$HOME/prompt-ready"
zpty -w -n shell $'!!\n'
expect_probe 'echo ds-history-expansion||*' 'history expansion ran without review'
zpty -w -n shell $'\x15'
zpty -w shell 'echo ds-suggestion-value'
await_file "$HOME/prompt-ready"
zpty -w -n shell 'echo ds-sugg'
zselect -t 10
# Request after batched terminal input.
zpty -w -n shell $'\x18\x06'
expect_probe 'echo ds-sugg|estion-value|*' 'autosuggestion missing'
zpty -w -n shell $'\x00'
expect_probe 'echo ds-suggestion-value||*' 'autosuggestion acceptance failed'

zpty -w -n shell $'\x15ds_missing_command'
zselect -t 10
expect_probe '*fg=red*' 'syntax highlight missing'
zpty -w -n shell $'\x15'
zpty -w -n shell 'echo value # comment'
expect_probe 'echo value # comment||*standout*' 'comment highlight missing'
zpty -w -n shell $'\x15'
zpty -w shell 'exit'
print -r -- "plugins: $DS_TEST_MODE ok"
