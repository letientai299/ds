#!/bin/sh

set -eu
root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-checksum.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM
fail() {
	printf '%s\n' "checksum: $*" >&2
	exit 1
}
DS_SHA_TOOL=$(command -v shasum)
export DS_SHA_TOOL DS_SHA_LOG="$work/calls"
mkdir -p "$work/bundle/files" "$work/tools" "$work/empty"
printf 'ds-bundle-v1\tfixture\n' >"$work/bundle/manifest.tsv"
for name in first 'with spaces' '-'; do
	printf '%s\n' "$name" >"$work/bundle/files/$name"
	digest=$("$DS_SHA_TOOL" -a 256 "$work/bundle/files/$name")
	printf 'file\t0644\t%s\t%s\n' "${digest%% *}" "$name" >>"$work/bundle/manifest.tsv"
done
digest=$("$DS_SHA_TOOL" -a 256 "$work/bundle/manifest.tsv")
manifest=${digest%% *}
cat >"$work/tools/sha256sum" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DS_SHA_LOG"
if [ "${DS_NO_CHECK:-false}" = true ] && [ "$1" = -c ]; then exit 1; fi
exec "$DS_SHA_TOOL" -a 256 "$@"
SH
chmod 0755 "$work/tools/sha256sum"
verify() {
	PATH="$work/tools" "$root/src/bootstrap.sh" --source "$work/bundle" --manifest-sha256 "$manifest" --verify-only
}
verify >"$work/out"
[ "$(wc -l <"$DS_SHA_LOG" | tr -d ' ')" -eq 2 ] || fail 'verification did not batch digests'
: >"$DS_SHA_LOG"
DS_NO_CHECK=true verify >"$work/out"
[ "$(wc -l <"$DS_SHA_LOG" | tr -d ' ')" -eq 5 ] || fail 'legacy fallback did not check every file'
PATH="$work/empty" "$root/src/bootstrap.sh" --source "$work/bundle" --manifest-sha256 "$manifest" --verify-only >"$work/out" 2>"$work/err"
grep -q 'controller verification is authoritative' "$work/err" || fail 'minimal-host warning missing'
# Exercise shasum selection as well.
mv "$work/tools/sha256sum" "$work/tools/shasum"
cat >"$work/tools/shasum" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DS_SHA_LOG"
exec "$DS_SHA_TOOL" "$@"
SH
: >"$DS_SHA_LOG"
verify >"$work/out"
[ "$(wc -l <"$DS_SHA_LOG" | tr -d ' ')" -eq 2 ] || fail 'shasum did not batch'
for name in first 'with spaces' '-'; do
	cp "$work/bundle/files/$name" "$work/original"
	printf '%s\n' corrupt >"$work/bundle/files/$name"
	if verify >"$work/out" 2>"$work/err"; then fail "tampering accepted: $name"; fi
	cp "$work/original" "$work/bundle/files/$name"
done
printf '%s\n' 'checksum: ok'
