#!/usr/bin/env zsh
setopt err_exit no_unset pipe_fail
root=${0:A:h:h}
work=$(mktemp -d)
trap 'command rm -rf -- "$work"' EXIT

fail() {
  print -ru2 -- "$1"
  exit 1
}

mkdir -p "$work/bin"
printf '#!/bin/sh\n[ "$1" != --version ] || exit 0\nprintf delta\n' > "$work/bin/delta"
printf '#!/bin/sh\nprintf less\n' > "$work/bin/less"
chmod +x "$work/bin/"*
pager=$(git config --file "$root/assets/dotfiles/gitconfig" core.pager)
[[ $(PATH="$work/bin" /bin/sh -c "$pager") == delta ]] || fail 'Delta pager failed'
printf '#!/bin/sh\nexit 1\n' > "$work/bin/delta"
[[ $(PATH="$work/bin" /bin/sh -c "$pager") == less ]] || fail 'Broken delta fallback failed'
command rm "$work/bin/delta"
[[ $(PATH="$work/bin" /bin/sh -c "$pager") == less ]] || fail 'Missing delta fallback failed'

print 'Git pager checks passed.'
