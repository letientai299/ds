set -eu
work=$DS_TEST_WORK

fail() {
  print -ru2 -- "navigation: $*"
  exit 1
}

mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/ds"
print -r -- starship > "${XDG_CONFIG_HOME:-$HOME/.config}/ds/components"
source "$DS_TEST_SRC/dotfiles/shell.zsh"
[[ $MISE_ENV != *starship* ]] || fail 'retired prompt profile remains'
[[ -o interactive_comments && -o no_beep && -o ignore_eof ]] || fail 'shell options missing'
(( ! $+functions[n] )) || fail 'nnn wrapper remains'
[[ $aliases[so] == source && $aliases[:q] == exit ]] || fail 'shortcuts missing'
[[ $aliases[wrap] == 'tput smam' && $aliases[nowrap] == 'tput rmam' ]] || fail 'wrapping shortcuts missing'
[[ ! -e $work/fd-calls ]] || fail 'startup scanned directories'

mkdir -p "$work/repo/remembered space" "$work/repo/fresh space" "$work/repo/.ai/nested" "$work/repo-other"
cd "$work/repo/fresh space"
j remembered
[[ $PWD == "$work/repo/remembered space" ]] || fail 'jump escaped repository'
[[ ! -e $work/fd-calls ]] || fail 'remembered jump scanned directories'
j
[[ $PWD == "$work/repo/fresh space" ]] || fail 'picker scope changed'
[[ $(<$work/candidates) == $'fresh space/\n.ai/nested/\n.ai/' ]] || fail 'directory results changed'
[[ $(<$work/fd-calls) == *'--type d'*'--search-path .ai'* ]] || fail 'directory scan escaped roots'
code=0
DS_TEST_CANCEL=1 j || code=$?
[[ $code == 130 && $PWD == "$work/repo/fresh space" ]] || fail 'cancel changed directory'
mkdir -p "$work/outside/fresh space"
cd "$work/outside"
j
[[ $PWD == "$work/outside/fresh space" ]] || fail 'outside scope changed'

export EDITOR="$work/bin/editor"
cd "$work/linked tree"
local_todo
[[ $(<$work/edited) == "$work/repo/.dump/todo.md" ]] || fail 'todo escaped common repository'
[[ -d $work/repo/.dump && ! -d "$work/linked tree/.dump" ]] || fail 'todo duplicated per worktree'

fpath=("$DS_TEST_SRC/dotfiles/completions" $fpath)
autoload -Uz _ssh_hosts
zstyle ':completion:*:hosts' known-hosts-files "$HOME/.ssh/known_hosts"
curcontext=':ssh:'
words=(ssh '')
_wanted() {
  case $3 in
    'configured SSH host') print -rl -- "${config_hosts[@]}" ;;
    'known SSH host') print -rl -- "${known_hosts[@]}" ;;
  esac
}
print -r -- $'  Host local-alias LOCAL-ALIAS !excluded *.invalid\n  HostName host.internal\nInclude "conf.d/*.conf"\nInclude absent*\nInclude config' > "$HOME/.ssh/config"
print -r -- $'Host included-alias\nInclude config' > "$HOME/.ssh/conf.d/one.conf"
print -r -- $'known-alias,HOST.INTERNAL ssh-ed25519 key\n[port-alias]:2222 ssh-ed25519 key\n|1|hash|value ssh-ed25519 key\n@cert-authority cert-alias ssh-ed25519 key\nKNOWN-ALIAS ssh-ed25519 key\n' > "$HOME/.ssh/known_hosts"
actual=$(_ssh_hosts)
expected=$'local-alias\nincluded-alias\nknown-alias\nport-alias\ncert-alias'
[[ $actual == $expected ]] || fail "SSH candidates: $actual"
PREFIX='host.'
[[ $(_ssh_hosts) == *'HOST.INTERNAL'* ]] || fail 'explicit FQDN completion missing'
PREFIX=''
print -r -- 'Host rotated-alias' > "$HOME/.ssh/conf.d/two.conf"
[[ $(_ssh_hosts) == *rotated-alias* ]] || fail 'SSH include changes stayed stale'
print -rn -- 'Host custom-alias' > "$HOME/custom-ssh"
words=(ssh -F "$HOME/custom-ssh" '')
actual=$(_ssh_hosts)
[[ $actual == custom-alias* && $actual != *local-alias* ]] || fail 'SSH custom config ignored'
zstyle ':completion:*:hosts' hosts explicit-alias
[[ $(_ssh_hosts) == explicit-alias ]] || fail 'SSH style override ignored'
print -r -- 'navigation: ok'
