#!/bin/sh

set -eu

fail() {
	printf '%s\n' "controller: $*" >&2
	exit 1
}

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-controller-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export DS_FAKE_REMOTE_HOME="$work/remote-home"
mkdir -p "$DS_FAKE_REMOTE_HOME"
cp "$root/tests/fake-ssh.sh" "$work/fake-ssh"
chmod 0755 "$work/fake-ssh"

first=$(
	DS_SSH=$work/fake-ssh "$root/ds" push fixture core \
		--prefix .local/share/ds-controller \
		--deliver-only
)
[ -x "$first/ds" ] || fail 'controller did not install ds'
HOME=$DS_FAKE_REMOTE_HOME \
	XDG_CONFIG_HOME=$DS_FAKE_REMOTE_HOME/.config \
	XDG_DATA_HOME=$DS_FAKE_REMOTE_HOME/.local/share \
	XDG_STATE_HOME=$DS_FAKE_REMOTE_HOME/.local/state \
	MISE_CONFIG_DIR=$DS_FAKE_REMOTE_HOME/.config/ds/mise \
	MISE_DATA_DIR=$DS_FAKE_REMOTE_HOME/.local/share/mise \
	MISE_STATE_DIR=$DS_FAKE_REMOTE_HOME/.local/state/mise \
	"$first/ds" status core >"$work/status.out"
if ! grep -q '^core: incomplete$' "$work/status.out"; then
	cat "$work/status.out" >&2
	fail 'controller snapshot did not resolve core'
fi

second=$(
	DS_SSH=$work/fake-ssh "$root/ds" push fixture core \
		--prefix .local/share/ds-controller \
		--deliver-only
)
[ "$first" = "$second" ] || fail 'same-content push was not idempotent'

remote_prefix=$DS_FAKE_REMOTE_HOME/.local/share/ds-controller
[ ! -L "$remote_prefix/current" ] || fail 'deliver-only activated the snapshot'
"$first/ds" activate "$(basename "$first")" --prefix "$remote_prefix" >/dev/null
[ "$(readlink "$remote_prefix/current")" = "versions/$(basename "$first")" ] || fail 'activation failed'

# Every earlier push delivered byte-identical content, so the content-addressed
# version never changed and the upgrade path was never exercised.
mkdir -p "$work/nvim-alt"
git -C "$work/nvim-alt" init -q
printf '%s\n' '-- alternate configuration' >"$work/nvim-alt/init.lua"
git -C "$work/nvim-alt" add init.lua
git -C "$work/nvim-alt" -c user.email=ds@example.invalid -c user.name=ds commit -qm alternate
upgraded=$(
	DS_NVIM_SOURCE=$work/nvim-alt DS_SSH=$work/fake-ssh "$root/ds" push fixture core \
		--prefix .local/share/ds-controller \
		--deliver-only
)
[ "$upgraded" != "$first" ] || fail 'changed payload produced the same version'
[ -x "$upgraded/ds" ] || fail 'upgrade push did not install ds'
[ "$(readlink "$remote_prefix/current")" = "versions/$(basename "$first")" ] || fail 'staging changed current'
"$first/ds" activate "$(basename "$upgraded")" --prefix "$remote_prefix" >/dev/null
[ "$(readlink "$remote_prefix/current")" = "versions/$(basename "$upgraded")" ] || fail 'upgrade activation failed'
"$upgraded/ds" rollback --prefix "$remote_prefix" >/dev/null
[ "$(readlink "$remote_prefix/current")" = "versions/$(basename "$first")" ] || fail 'rollback failed'
[ -x "$remote_prefix/current/ds" ] || fail 'current does not resolve after the upgrade'

preview=$(
	DS_SSH=$work/fake-ssh "$root/ds" push fixture core \
		--prefix .local/share/ds-controller \
		--home .local/share/ds-controller-test-home \
		--dry-run 2>"$work/preview.err"
)
[ "$preview" = "$first" ] || fail 'push-and-preview returned the wrong installed path'
[ "$(readlink "$remote_prefix/current")" = "versions/$(basename "$first")" ] || fail 'preview changed current'
grep -q '^would apply core:$' "$work/preview.err" || fail 'controller did not invoke remote layer preview'
DS_SSH=$work/fake-ssh "$root/ds" push fixture core extra \
	--prefix .local/share/ds-controller \
	--home .local/share/ds-controller-test-home \
	--dry-run >"$work/multi.out" 2>"$work/multi.err"
grep -q '^would apply core,extra:$' "$work/multi.err" || fail 'controller did not pass multiple layers'
[ -d "$DS_FAKE_REMOTE_HOME/.local/share/ds-controller-test-home" ] || fail 'controller did not create the isolated remote home'
[ ! -e "$DS_FAKE_REMOTE_HOME/.local/share/ds-controller-test-home/.config" ] || fail 'remote layer preview wrote configuration'

if DS_SSH=$work/fake-ssh "$root/ds" push fixture core \
	--home ../unsafe --deliver-only >"$work/unsafe.out" 2>"$work/unsafe.err"; then
	fail 'controller accepted an unsafe remote home'
fi
grep -q 'home must be a safe relative path' "$work/unsafe.err" || fail 'unsafe home diagnostic is missing'

if DS_SSH=$work/fake-ssh "$root/ds" push fixture core \
	--dry-run --deliver-only >"$work/exclusive.out" 2>"$work/exclusive.err"; then
	fail 'controller accepted mutually exclusive modes'
fi
grep -q 'mutually exclusive' "$work/exclusive.err" || fail 'mutually exclusive diagnostic is missing'

target_home=$DS_FAKE_REMOTE_HOME/.local/share/ds-controller-test-home
mkdir -p "$target_home/.config/nvim"
printf '%s\n' original >"$target_home/.config/nvim/keep"
for flag in --force --adopt; do
	if DS_SSH=$work/fake-ssh "$root/ds" push fixture core \
		"$flag" --deliver-only >"$work/exclusive.out" 2>"$work/exclusive.err"; then
		fail 'controller accepted force without application'
	fi
	grep -q 'remove --deliver-only' "$work/exclusive.err" || fail 'force diagnostic missing'
	DS_SSH=$work/fake-ssh "$root/ds" push fixture core \
		--prefix .local/share/ds-controller \
		--home .local/share/ds-controller-test-home \
		"$flag" --dry-run >"$work/force.out" 2>"$work/force.err"
	grep -Fq "backup $target_home/.config/nvim -> $target_home/.config/nvim.ds-adopted" "$work/force.err" || fail 'remote force omitted backup'
	[ "$(cat "$target_home/.config/nvim/keep")" = original ] || fail 'preview changed conflict'
	[ ! -e "$target_home/.config/nvim.ds-adopted" ] || fail 'preview created backup'
	[ "$(readlink "$remote_prefix/current")" = "versions/$(basename "$first")" ] || fail 'force preview changed current'
done

printf '%s\n' '#!/bin/sh' 'exit 0' >"$work/mise"
chmod 0755 "$work/mise"
DS_MISE=$work/mise DS_SSH=$work/fake-ssh "$root/ds" push fixture core \
	--prefix .local/share/ds-controller \
	--home .local/share/ds-controller-test-home \
	--force >"$work/force.out" 2>"$work/force.err"
[ -L "$target_home/.config/nvim" ] || fail 'remote force did not apply'
[ "$(cat "$target_home/.config/nvim.ds-adopted/keep")" = original ] || fail 'remote force lost original'

printf '%s\n' 'controller: ok'
