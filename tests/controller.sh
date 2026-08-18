#!/bin/sh

set -eu

fail() {
	printf '%s\n' "controller: $*" >&2
	exit 1
}

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/df-controller-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export DF_FAKE_REMOTE_HOME="$work/remote-home"
mkdir -p "$DF_FAKE_REMOTE_HOME"
printf '%s\n' \
	'#!/bin/sh' \
	'shift' \
	"HOME=\$DF_FAKE_REMOTE_HOME exec /bin/sh -c \"\$1\"" >"$work/fake-ssh"
chmod 0755 "$work/fake-ssh"

first=$(
	DF_SSH=$work/fake-ssh "$root/ds" push fixture core \
		--prefix .local/share/df-controller \
		--deliver-only
)
[ -x "$first/ds" ] || fail 'controller did not install ds'
HOME=$DF_FAKE_REMOTE_HOME \
	XDG_CONFIG_HOME=$DF_FAKE_REMOTE_HOME/.config \
	XDG_DATA_HOME=$DF_FAKE_REMOTE_HOME/.local/share \
	XDG_STATE_HOME=$DF_FAKE_REMOTE_HOME/.local/state \
	MISE_CONFIG_DIR=$DF_FAKE_REMOTE_HOME/.config/df/mise \
	MISE_DATA_DIR=$DF_FAKE_REMOTE_HOME/.local/share/mise \
	MISE_STATE_DIR=$DF_FAKE_REMOTE_HOME/.local/state/mise \
	"$first/ds" status core >"$work/status.out"
if ! grep -q '^core: incomplete$' "$work/status.out"; then
	cat "$work/status.out" >&2
	fail 'controller snapshot did not resolve core'
fi

second=$(
	DF_SSH=$work/fake-ssh "$root/ds" push fixture core \
		--prefix .local/share/df-controller \
		--deliver-only
)
[ "$first" = "$second" ] || fail 'same-content push was not idempotent'

preview=$(
	DF_SSH=$work/fake-ssh "$root/ds" push fixture core \
		--prefix .local/share/df-controller \
		--home .local/share/df-controller-test-home \
		--dry-run 2>"$work/preview.err"
)
[ "$preview" = "$first" ] || fail 'push-and-preview returned the wrong installed path'
grep -q '^would apply core:$' "$work/preview.err" || fail 'controller did not invoke remote layer preview'
[ -d "$DF_FAKE_REMOTE_HOME/.local/share/df-controller-test-home" ] || fail 'controller did not create the isolated remote home'
[ ! -e "$DF_FAKE_REMOTE_HOME/.local/share/df-controller-test-home/.config" ] || fail 'remote layer preview wrote configuration'

if DF_SSH=$work/fake-ssh "$root/ds" push fixture core \
	--home ../unsafe --deliver-only >"$work/unsafe.out" 2>"$work/unsafe.err"; then
	fail 'controller accepted an unsafe remote home'
fi
grep -q 'home must be a safe relative path' "$work/unsafe.err" || fail 'unsafe home diagnostic is missing'

if DF_SSH=$work/fake-ssh "$root/ds" push fixture core \
	--dry-run --deliver-only >"$work/exclusive.out" 2>"$work/exclusive.err"; then
	fail 'controller accepted mutually exclusive modes'
fi
grep -q 'mutually exclusive' "$work/exclusive.err" || fail 'mutually exclusive diagnostic is missing'

printf '%s\n' 'controller: ok'
