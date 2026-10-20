#!/usr/bin/env zsh
setopt err_exit no_unset pipe_fail
root=${0:A:h:h}
work=$(mktemp -d)
trap 'command rm -rf -- "$work"' EXIT
mkdir -p "$work/mise/installs/zoxide/latest"
cat > "$work/mise/installs/zoxide/latest/zoxide" <<'SH'
#!/bin/sh
printf 'init\n' >> "$ZOXIDE_LOG"
cat <<'ZSH'
_test_zoxide() { :; }
if (( $+functions[compdef] )); then
  compdef _test_zoxide z
fi
ZSH
SH
chmod +x "$work/mise/installs/zoxide/latest/zoxide"

for mode in fresh initialized; do
  ROOT="$root" WORK="$work" MODE="$mode" zsh -dfi -c '
setopt err_exit
export XDG_DATA_HOME="$WORK/data" XDG_CACHE_HOME="$WORK/cache"
export MISE_DATA_DIR="$WORK/mise" ZOXIDE_LOG="$WORK/$MODE.log"
_ds_config_dir="$WORK/config"
typeset -a queue
zsh-defer() { queue+=("${@[-1]}"); }
if [[ $MODE == initialized ]]; then
  autoload -Uz compinit
  compinit -D -i
fi
source "$ROOT/assets/dotfiles/interactive.zsh"
_ds_worktrunk_init() { return 0; }
[[ ! -e $ZOXIDE_LOG ]] || exit 1
for callback in "${queue[@]}"; do
  "$callback"
  [[ $callback != _ds_tool_init ]] || break
done
[[ ${_comps[z]:-} == _test_zoxide ]] || {
  print -ru2 -- "Missing zoxide completion: $MODE"
  exit 2
}
_ds_tool_init
[[ $(<"$ZOXIDE_LOG") == init ]] || exit 3
'
done
print 'Zoxide completion checks passed.'
