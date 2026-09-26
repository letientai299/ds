#!/bin/sh

set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-update.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM
unset DS_NVIM_SOURCE DS_TMUX_SOURCE DS_KITTY_SOURCE
export XDG_CONFIG_HOME="$work/config"
export DS_TEST_SETUP_LOG="$work/setup.log"
: >"$DS_TEST_SETUP_LOG"

fail() {
	printf '%s\n' "update test: $*" >&2
	exit 1
}

commit() {
	git -C "$1" -c user.name=Test -c user.email=test@example.invalid \
		-c commit.gpgsign=false commit -qm "$2"
}

reject() {
	setups=$(wc -l <"$DS_TEST_SETUP_LOG")
	if "$work/checkout/ds" update "$@" >"$work/output" 2>&1; then
		fail 'unsafe update succeeded'
	fi
	[ "$(git -C "$work/checkout" rev-parse HEAD)" = "$before" ] || fail 'failed update changed HEAD'
	[ "$(wc -l <"$DS_TEST_SETUP_LOG")" = "$setups" ] || fail 'failed update ran setup'
}

git init -q --bare "$work/remote.git"
git init -q -b main "$work/source"
mkdir -p "$work/source/src/scripts" "$work/source/scripts"
cat >"$work/source/scripts/install.sh" <<'SH'
#!/bin/sh
set -eu
[ "$#" -eq 0 ]
root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd -P)
[ "$DS_INSTALL_UPDATED_ROOT" = "$root" ]
[ -z "${DS_UPDATE_SOURCE_ONLY:-}" ]
printf 'setup %s\n' "$(tail -1 "$root/content")" >>"$DS_TEST_SETUP_LOG"
exit "${DS_TEST_SETUP_STATUS:-0}"
SH
cp "$root/ds" "$work/source/ds"
cp "$root/src/scripts/update.sh" "$work/source/src/scripts/update.sh"
printf '%s\n' initial >"$work/source/content"
git -C "$work/source" add ds scripts/install.sh src/scripts/update.sh content
commit "$work/source" initial
git -C "$work/source" remote add origin "$work/remote.git"
git -C "$work/source" push -qu origin main
git clone -q -b main "$work/remote.git" "$work/checkout"
before=$(git -C "$work/checkout" rev-parse HEAD)

# Launcher resolution ignores cwd and stale roots.
mkdir -p "$work/bin"
ln -s "$work/checkout/ds" "$work/bin/ds"
cd "$work/source"
DS_ROOT=/missing DS_JANET=/missing "$work/bin/ds" update --help >"$work/output"
grep -q '^usage: ds update' "$work/output" || fail 'help missing'
reject --force
reject --help extra

printf '%s\n' updated >"$work/source/content"
git -C "$work/source" add content
commit "$work/source" updated
git -C "$work/source" push -q

printf '%s\n' dirty >>"$work/checkout/content"
reject
grep -q 'uncommitted changes' "$work/output" || fail 'dirty checkout diagnostic missing'
git -C "$work/checkout" add content
reject
git -C "$work/checkout" restore --staged --worktree content
printf '%s\n' untracked >"$work/checkout/local"
reject
[ "$(cat "$work/checkout/local")" = untracked ] || fail 'untracked file changed'
rm "$work/checkout/local"

for name in nvim tmux kitty; do
	git clone -q -b main "$work/remote.git" "$work/$name.conf"
done
mv "$work/tmux.conf" "$work/custom tmux"
export DS_TMUX_SOURCE="$work/custom tmux"
printf '%s\n' dependencies >>"$work/source/content"
git -C "$work/source" add content
commit "$work/source" dependencies
git -C "$work/source" push -q

printf '%s\n' dirty >"$work/kitty.conf/local"
reject
grep -q 'kitty.conf' "$work/output" || fail 'dependency diagnostic missing'
[ "$(cat "$work/nvim.conf/content")" = updated ] || fail 'preflight changed dependency'
rm "$work/kitty.conf/local"
(DS_NVIM_SOURCE="$work/missing" reject)
grep -q 'source is missing' "$work/output" || fail 'missing override accepted'
mkdir -p "$work/not a checkout"
(DS_NVIM_SOURCE="$work/not a checkout" reject)
grep -q 'requires a Git checkout' "$work/output" || fail 'noncheckout override accepted'

DS_ROOT=/missing DS_JANET=/missing "$work/bin/ds" update >"$work/output" 2>&1 || {
	cat "$work/output"
	fail 'dependency update failed'
}
for checkout in checkout nvim.conf 'custom tmux' kitty.conf; do
	cmp "$work/source/content" "$work/$checkout/content" || fail "update missed $checkout"
done
[ "$(grep '^ds update: pulling ' "$work/output" | tail -1)" = "ds update: pulling $(cd "$work/checkout" && pwd -P)" ] || fail 'ds was not updated last'
grep -qx 'setup dependencies' "$DS_TEST_SETUP_LOG" || fail 'setup did not follow pulls'
[ "$(wc -l <"$DS_TEST_SETUP_LOG" | tr -d ' ')" = 1 ] || fail 'setup ran more than once'
if DS_TEST_SETUP_STATUS=42 "$work/bin/ds" update >"$work/output" 2>&1; then
	fail 'setup failure was ignored'
else
	[ "$?" -eq 42 ] || fail 'setup failure status changed'
fi
before=$(git -C "$work/checkout" rev-parse HEAD)
DS_NVIM_SOURCE="$work/kitty.conf" DS_TMUX_SOURCE="$work/kitty.conf" \
	"$work/bin/ds" update >"$work/output" 2>&1
[ "$(grep -c '^ds update: pulling ' "$work/output")" -eq 2 ] || fail 'duplicate checkout updated twice'
"$work/bin/ds" update >"$work/output" 2>&1
[ "$(git -C "$work/checkout" rev-parse HEAD)" = "$before" ] || fail 'repeat update changed HEAD'

# Installed links locate non-sibling configuration repos.
mkdir -p "$XDG_CONFIG_HOME/ds"
for name in nvim kitty; do
	mv "$work/$name.conf" "$work/custom $name"
done
ln -s "$work/custom nvim" "$XDG_CONFIG_HOME/nvim"
ln -s "$work/custom tmux" "$XDG_CONFIG_HOME/tmux"
ln -s "$work/custom kitty" "$XDG_CONFIG_HOME/ds/kitty"
unset DS_TMUX_SOURCE
printf '%s\n' linked >>"$work/source/content"
git -C "$work/source" add content
commit "$work/source" linked
git -C "$work/source" push -q
"$work/bin/ds" update >"$work/output" 2>&1
for name in nvim tmux kitty; do
	cmp "$work/source/content" "$work/custom $name/content" || fail "update missed installed $name"
done
before=$(git -C "$work/checkout" rev-parse HEAD)

git -C "$work/checkout" checkout -q --detach
reject
grep -q 'detached HEAD' "$work/output" || fail 'detached diagnostic missing'
git -C "$work/checkout" checkout -q main
git -C "$work/checkout" branch --unset-upstream
reject
grep -q 'no upstream' "$work/output" || fail 'upstream diagnostic missing'
git -C "$work/checkout" branch -u origin/main >/dev/null

git -C "$work/checkout" worktree add -q -b feature "$work/linked checkout" main
git -C "$work/linked checkout" branch -u origin/main >/dev/null
"$work/linked checkout/ds" update >"$work/output" 2>&1
[ "$(git -C "$work/linked checkout" branch --show-current)" = feature ] || fail 'update switched branches'

printf '%s\n' local >"$work/checkout/local"
git -C "$work/checkout" add local
commit "$work/checkout" local
before=$(git -C "$work/checkout" rev-parse HEAD)
printf '%s\n' divergent >>"$work/source/content"
git -C "$work/source" add content
commit "$work/source" divergent
git -C "$work/source" push -q
git -C "$work/checkout" config pull.rebase true
reject
[ "$(cat "$work/checkout/local")" = local ] || fail 'divergence lost local commit'

git -C "$work/checkout" remote set-url origin "$work/missing.git"
reject

mkdir -p "$work/snapshot/src/scripts"
cp "$root/ds" "$work/snapshot/ds"
cp "$root/src/scripts/update.sh" "$work/snapshot/src/scripts/update.sh"
if "$work/snapshot/ds" update >"$work/output" 2>&1; then
	fail 'snapshot update succeeded'
fi
grep -q 'requires a Git checkout' "$work/output" || fail 'snapshot diagnostic missing'

printf '%s\n' 'update: ok'
