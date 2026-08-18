#!/bin/sh

set -eu

die() {
	printf '%s\n' "df runtime reproducibility: $*" >&2
	exit 1
}

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
source_dist=${DF_RUNTIME_DIST:-$root/dist/runtime}
work=$(mktemp -d "${TMPDIR:-/tmp}/df-runtime-reproducible.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
dist=$work/runtime
mkdir -p "$dist"
cp -R "$source_dist/src" "$dist/src"
export DF_RUNTIME_DIST="$dist"

if command -v sha256sum >/dev/null 2>&1; then
	checksum_kind=sha256sum
elif command -v shasum >/dev/null 2>&1; then
	checksum_kind=shasum
else
	die 'a SHA-256 utility is required'
fi

sha256_file() {
	case "$checksum_kind" in
	sha256sum) sha256sum "$1" | {
		read -r digest _rest
		printf '%s\n' "$digest"
	} ;;
	shasum) shasum -a 256 "$1" | {
		read -r digest _rest
		printf '%s\n' "$digest"
	} ;;
	esac
}

matrix_checksums() {
	for platform in macos-arm64 macos-x64 linux-arm64-musl linux-x64-musl; do
		binary=$dist/bin/$platform/janet
		[ -x "$binary" ] || die "runtime is missing: $platform"
		printf '%s\t%s\n' "$platform" "$(sha256_file "$binary")"
	done
}

"$root/runtime/build.sh" all >/dev/null
before=$(matrix_checksums)
"$root/runtime/build.sh" all >/dev/null
after=$(matrix_checksums)

if [ "$before" != "$after" ]; then
	printf '%s\n' "$before" >&2
	printf '%s\n' "$after" >&2
	die 'same-input builds produced different checksums'
fi

printf '%s\n' "$after"
printf '%s\n' 'runtime reproducibility: ok'
