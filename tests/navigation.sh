#!/bin/sh
set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-navigation.XXXXXX")
work=$(CDPATH='' cd -P "$work" && pwd)
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM
mkdir -p "$work/bin" "$work/home/.ssh/conf.d" "$work/repo"
git init -qb main "$work/repo"
git -C "$work/repo" -c user.name=Test -c user.email=test@example.invalid \
	commit -q --allow-empty -m initial
git -C "$work/repo" worktree add -qb feature "$work/linked tree"
cat >"$work/bin/zoxide" <<'SH'
#!/bin/sh
printf '%s\n' "$DS_TEST_WORK/repo-other" "$DS_TEST_WORK/repo/remembered space"
SH
cat >"$work/bin/fzf" <<'SH'
#!/bin/sh
cat >"$DS_TEST_WORK/candidates"
[ "${DS_TEST_CANCEL:-0}" = 0 ] || exit 130
printf '%s\n' 'fresh space/'
SH
cat >"$work/bin/fd" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DS_TEST_WORK/fd-calls"
case " $* " in
*' --no-ignore '*) printf '%s\n' '.ai/nested/' 'fresh space/' ;;
*) printf '%s\n' 'fresh space/' ;;
esac
SH
cat >"$work/bin/editor" <<'SH'
#!/bin/sh
printf '%s\n' "$1" >"$DS_TEST_WORK/edited"
SH
chmod +x "$work/bin/"*
ln -s "${1:-$root/src}/tools/fzf-dirs" "$work/bin/fzf-dirs"
env -i HOME="$work/home" PATH="$work/bin:$PATH" TERM=dumb \
	DS_SHELL_ROOT="$root" DS_TEST_SRC="${1:-$root/src}" DS_TEST_WORK="$work" \
	zsh -df "$root/tests/navigation.zsh"
