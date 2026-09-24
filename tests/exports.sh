#!/bin/sh
set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-exports.XXXXXX")
work=$(CDPATH='' cd -P "$work" && pwd)
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM
mkdir -p "$work/bin" "$work/home" "$work/repo/.ai" "$work/repo/.dump"
touch "$work/repo/.env" "$work/repo/.env.local"
ln -s "$(command -v zsh)" "$work/bin/zsh"
ln -s "$(command -v awk)" "$work/bin/awk"
ln -s "${1:-$root/src}/tools/fzf-files" "$work/bin/fzf-files"
cat >"$work/bin/fd" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DS_TEST_WORK/fd-calls"
[ "${DS_TEST_FD_FAIL:-0}" = 0 ] || exit 71
case " $* " in
*' --no-ignore '*) printf '%s\n' '.ai/shared.txt' '.dump/hidden.txt' ;;
*) printf '%s\n' 'file space.txt' '.ai/shared.txt' ;;
esac
SH
chmod +x "$work/bin/fd"
env -i HOME="$work/home" PATH="$PATH" TERM=dumb \
	DS_TEST_SRC="${1:-$root/src}" DS_TEST_WORK="$work" \
	zsh -df "$root/tests/exports.zsh"
