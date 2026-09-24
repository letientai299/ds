#!/bin/sh

set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-push-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM

die() {
	printf '%s\n' "push test: $*" >&2
	exit 1
}

# shellcheck source=src/lib/checksum.sh
. "$root/src/lib/checksum.sh"
snapshot=$work/snapshot
mkdir -p "$snapshot/files/src"
cp "$root/src/bootstrap.sh" "$snapshot/files/src/bootstrap.sh"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" delivered' >"$snapshot/files/ds"
chmod 0755 "$snapshot/files/ds"
index=0
while [ "$index" -lt 20 ]; do
	printf '%s\n' "$index" >"$snapshot/files/src/file-$index"
	index=$((index + 1))
done
tab=$(printf '\t')
printf 'ds-bundle-v1%sfixture\n' "$tab" >"$snapshot/manifest.tsv"
find "$snapshot/files" -type f | sort | while IFS= read -r file; do
	mode=0644
	[ ! -x "$file" ] || mode=0755
	printf 'file%s%s%s%s%s%s\n' "$tab" "$mode" "$tab" "$(sha256_file "$file")" "$tab" "${file#"$snapshot/files/"}"
done >>"$snapshot/manifest.tsv"
sha256_file "$snapshot/manifest.tsv" >"$snapshot/manifest.sha256"
printf '%s\n' unlisted >"$snapshot/files/unlisted"
cp "$root/tests/fake-ssh.sh" "$work/ssh"
chmod 0755 "$work/ssh"
export DS_SSH="$work/ssh" DS_SSH_LOG="$work/ssh.log"
export DS_SSH_CONTROL_LOG="$work/control.log"
export TMPDIR="$work/long-temporary-directory-exceeding-macos-socket-limits/with spaces"
mkdir -p "$TMPDIR"

check_control() {
	[ "$(sort -u "$DS_SSH_CONTROL_LOG" | wc -l | tr -d ' ')" -eq 1 ] || die 'push did not reuse its socket'
	control_path=$(sed -n '1p' "$DS_SSH_CONTROL_LOG")
	[ ! -d "${control_path%/*}" ] || die 'push leaked its socket directory'
}

for mode in archive fallback; do
	export DS_FAKE_REMOTE_HOME="$work/$mode"
	mkdir -p "$DS_FAKE_REMOTE_HOME"
	: >"$DS_SSH_LOG"
	: >"$DS_SSH_CONTROL_LOG"
	DS_SSH_NO_TAR=false
	[ "$mode" != fallback ] || DS_SSH_NO_TAR=true
	export DS_SSH_NO_TAR
	installed=$("$root/src/bundle/push.sh" --snapshot "$snapshot" --host fixture)
	check_control
	[ "$("$installed/ds")" = delivered ] || die "$mode dispatch failed"
	[ "$(cat "$installed/src/file-19")" = 19 ] || die "$mode payload incomplete"
	[ ! -e "$DS_FAKE_REMOTE_HOME/.local/share/ds/incoming/fixture/files/unlisted" ] || die 'unlisted file transferred'
	calls=$(wc -l <"$DS_SSH_LOG" | tr -d ' ')
	case "$mode" in
	archive) [ "$calls" -eq 4 ] || die 'archive transfer opened extra commands' ;;
	fallback) [ "$calls" -eq 26 ] || die 'fallback transfer skipped files' ;;
	esac
	: >"$DS_SSH_LOG"
	: >"$DS_SSH_CONTROL_LOG"
	[ "$("$root/src/bundle/push.sh" --snapshot "$snapshot" --host fixture)" = "$installed" ] || die 'repeat push changed version'
	check_control
	[ "$(wc -l <"$DS_SSH_LOG" | tr -d ' ')" -eq 2 ] || die 'repeat push transferred payload'
done

: >"$DS_SSH_CONTROL_LOG"
printf '%s\n' tampered >"$snapshot/files/src/file-19"
if "$root/src/bundle/push.sh" --snapshot "$snapshot" --host fixture >/dev/null 2>&1; then
	die 'push accepted a corrupt snapshot'
fi
check_control

printf '%s\n' 'push: ok (archive=4, fallback=26 remote commands)'
