set -eu
work=$DS_TEST_WORK

function fail() {
  print -ru2 -- "exports: $*"
  exit 1
}

source "$DS_TEST_SRC/dotfiles/shell.zsh"
function reload() { source "$DS_TEST_SRC/dotfiles/shell.zsh"; }
reload
[[ $EDITOR == nvim ]] || fail 'editor changed'
[[ $FZF_DEFAULT_COMMAND == fzf-files && $FZF_CTRL_T_COMMAND == fzf-files ]] || fail 'FZF command changed'
[[ $FZF_DEFAULT_OPTS == '--height 80% --reverse' ]] || fail 'FZF layout changed'
[[ $RIPGREP_CONFIG_PATH == $XDG_CONFIG_HOME/ds/rgrc ]] || fail 'ripgrep escaped managed config'
[[ $HISTSIZE == 10000000 && $SAVEHIST == 10000000 ]] || fail 'history limits changed'
[[ -o hist_ignore_all_dups && -o hist_ignore_space ]] || fail 'history options missing'
[[ $LC_ALL == $LANG && $LC_CTYPE == $LANG && $LANG == *UTF-8 ]] || fail 'locale changed'
[[ ! -e $work/fd-calls ]] || fail 'startup scanned files'
[[ $(find "$HOME" -type f -print) == "$XDG_CACHE_HOME/ds/git-version" ]] || fail 'unexpected startup files'
[[ ${#path} == ${#${(u)path}} ]] || fail 'PATH contains duplicates'

cd "$work/repo"
expected=$'file space.txt\n.ai/shared.txt\n.dump/hidden.txt\n.env\n.env.local'
actual=$(PATH="$work/bin" "$work/bin/fzf-files")
[[ $actual == $expected ]] || fail 'file selection changed'
[[ $(<$work/fd-calls) == *'--search-path .ai --search-path .dump'* ]] || fail 'ignored scan escaped include roots'
(( $(wc -l <"$work/fd-calls") == 2 )) || fail 'unexpected search count'
mv "$work/bin/fd" "$work/bin/fdfind"
[[ $(PATH="$work/bin" "$work/bin/fzf-files") == $expected ]] || fail 'fdfind fallback failed'
code=0
DS_TEST_FD_FAIL=1 PATH="$work/bin" "$work/bin/fzf-files" >/dev/null || code=$?
[[ $code == 71 ]] || fail 'finder failure was hidden'
rm "$work/bin/fdfind"
code=0
PATH="$work/bin" "$work/bin/fzf-files" >/dev/null 2>"$work/error" || code=$?
[[ $code == 1 && $(<$work/error) == 'fzf-files: fd is unavailable' ]] || fail 'missing finder diagnostic changed'
print -r -- 'exports: ok'
