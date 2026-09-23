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
# shellcheck disable=SC2016 # The fake expands these at run time, not here.
printf '%s\n' \
	'#!/bin/sh' \
	'for argument in "$@"; do command=$argument; done' \
	"cd \"\$DS_FAKE_REMOTE_HOME\"" \
	"HOME=\$DS_FAKE_REMOTE_HOME exec /bin/sh -c \"\$command\"" >"$work/fake-ssh"
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
[ "$(readlink "$remote_prefix/current")" = "versions/$(basename "$first")" ] ||
	fail 'push did not point current at the delivered version'

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
[ "$(readlink "$remote_prefix/current")" = "versions/$(basename "$upgraded")" ] ||
	fail 'current did not follow the upgrade'
[ -x "$remote_prefix/current/ds" ] || fail 'current does not resolve after the upgrade'

preview=$(
	DS_SSH=$work/fake-ssh "$root/ds" push fixture core \
		--prefix .local/share/ds-controller \
		--home .local/share/ds-controller-test-home \
		--dry-run 2>"$work/preview.err"
)
[ "$preview" = "$first" ] || fail 'push-and-preview returned the wrong installed path'
grep -q '^would apply core:$' "$work/preview.err" || fail 'controller did not invoke remote layer preview'
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

printf '%s\n' 'controller: ok'
