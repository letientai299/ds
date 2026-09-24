setopt errexit interactive_comments

shell=$1
work=$2
mkdir -p "$HOME" "$work/one/two/three/four/five" "$work/spaced directory"

function fail() {
  print -ru2 -- "aliases: $*"
  exit 1
}

# Startup avoids Docker calls and cache writes.
function docker() { fail 'Docker ran during startup'; }
source "$shell"
function reload() { source "$shell"; }
reload
[[ -z $(command find "$HOME" -mindepth 1 -print) ]] || fail 'startup wrote files'

[[ -o auto_cd && -o auto_pushd && -o pushd_ignore_dups && -o pushdminus ]] || fail 'directory options missing'
cd "$work/one/two/three/four/five"
..
[[ $PWD == "$work/one/two/three/four" ]] || fail '.. failed'
...
[[ $PWD == "$work/one/two" ]] || fail '... failed'
cd "$work/one/two/three/four/five"
cd ....
[[ $PWD == "$work/one/two" ]] || fail 'global dots failed'
[[ $(print -r -- .. ... .... ..... ......) == '.. ../.. ../../.. ../../../.. ../../../../..' ]] || fail 'dot depths changed'
cd "$work"
"spaced directory"
[[ $PWD == "$work/spaced directory" ]] || fail 'auto-CD failed'
eval '-' >/dev/null
[[ $PWD == "$work" ]] || fail 'previous directory failed'
cd "$work/one"
eval '1' >/dev/null
[[ $PWD == "$work" ]] || fail 'directory stack failed'
[[ $(d) == *"$work"* ]] || fail 'directory listing failed'
md "$work/new directory/child"
rd "$work/new directory/child"
[[ -d "$work/new directory" && ! -e "$work/new directory/child" ]] || fail 'directory helpers failed'

function ls() { print -rl -- "$@"; }
[[ $(l 'spaced directory') == $'-lah\nspaced directory' ]] || fail 'l arguments changed'
[[ $(ll 'spaced directory') == $'-lh\nspaced directory' ]] || fail 'll arguments changed'
[[ $(la 'spaced directory') == $'-lAh\nspaced directory' ]] || fail 'la arguments changed'
[[ $(lsa 'spaced directory') == $'-lah\nspaced directory' ]] || fail 'lsa arguments changed'

function docker() { print -rl -- "$@"; }
function docker-compose() { print -rl -- compose "$@"; }
[[ $(dk image ls) == $'image\nls' ]] || fail 'dk arguments changed'
[[ $(dpsa) == $'ps\n-a' ]] || fail 'Docker aliases missing'
[[ $(dxcit 'container name' sh) == $'container\nexec\n-it\ncontainer name\nsh' ]] || fail 'Docker exec arguments changed'
[[ $(dc up -d) == $'compose\nup\n-d' ]] || fail 'dc changed'
[[ $(dp 'image:tag') == $'pull\nimage:tag' ]] || fail 'dp changed'
[[ $(dcp 'image:tag') == $'pull\nimage:tag' ]] || fail 'dcp changed'

command git init -q --initial-branch=main "$work/repo"
cd "$work/repo"
[[ $(git_current_branch) == main ]] || fail 'unborn branch failed'
command git -c user.name=Test -c user.email=test@example.invalid commit -qm initial --allow-empty
command git branch develop
command git checkout -qb feature
[[ $(git_main_branch) == main ]] || fail 'main branch failed'
[[ $(git_develop_branch) == develop ]] || fail 'develop branch failed'
gcm
[[ $(git_current_branch) == main ]] || fail 'main checkout failed'
gcd
[[ $(git_current_branch) == develop ]] || fail 'develop checkout failed'
function clipcopy() { command cat; }
[[ $(gbcopy) == develop ]] || fail 'branch clipboard failed'
command git checkout -q --detach
[[ $(git_current_branch) == $(command git rev-parse --short HEAD) ]] || fail 'detached branch failed'
command git checkout -q feature

function git() { print -rl -- "$@"; }
[[ $(ggp) == $'push\norigin\nfeature' ]] || fail 'current branch push failed'
[[ $(ggl other) == $'pull\norigin\nother' ]] || fail 'explicit branch pull failed'
[[ $(ggu) == $'pull\n--rebase\norigin\nfeature' ]] || fail 'current branch rebase failed'
[[ $(gs) == status && $(gst) == status ]] || fail 'status aliases missing'
[[ $(gcf!) == $'commit\n--amend\n--no-edit' ]] || fail 'custom amend changed'
[[ $(gdo) == $'diff\norigin/HEAD..HEAD' ]] || fail 'custom diff changed'
[[ $(gon) == open ]] || fail 'git-open alias changed'
[[ $(cm) == $'add\n.\ncommit\n-v' ]] || fail 'commit alias changed'

mkdir -p "$XDG_CONFIG_HOME/ds"
print -r -- "alias gs='git status --short'" >"$XDG_CONFIG_HOME/ds/local.zsh"
reload
[[ $(gs) == $'status\n--short' ]] || fail 'local override lost'

print -r -- 'aliases: ok'
exit 0
