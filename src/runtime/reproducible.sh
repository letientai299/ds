#!/bin/sh

set -eu

die() {
	printf '%s\n' "ds runtime reproducibility: $*" >&2
	exit 1
}

root=$(dirname -- "$0")/../..
root=$(CDPATH='' cd "$root" && pwd)
source_dist=${DS_RUNTIME_DIST:-$root/dist/runtime}
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-runtime-reproducible.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
dist=$work/runtime
mkdir -p "$dist"
cp -R "$source_dist/src" "$dist/src"
export DS_RUNTIME_DIST="$dist"

# shellcheck source=src/lib/checksum.sh
. "$root/src/lib/checksum.sh"

matrix_checksums() {
	for platform in macos-arm64 macos-x64 linux-arm64-musl linux-x64-musl; do
		binary=$dist/bin/$platform/janet
		[ -x "$binary" ] || die "runtime is missing: $platform"
		printf '%s\t%s\n' "$platform" "$(sha256_file "$binary")"
	done
}

# Without this the Linux halves of both passes are BuildKit cache hits and the
# comparison is sha256(x) == sha256(x). The toolchain stage stays cached, so a
# mirror update cannot turn this check red on its own.
export DS_RUNTIME_BUILD_FLAGS="--no-cache-filter build"

"$root/src/runtime/build.sh" all >/dev/null
before=$(matrix_checksums)
"$root/src/runtime/build.sh" all >/dev/null
after=$(matrix_checksums)

if [ "$before" != "$after" ]; then
	printf '%s\n' "$before" >&2
	printf '%s\n' "$after" >&2
	die 'same-input builds produced different checksums'
fi

printf '%s\n' "$after"
printf '%s\n' 'runtime reproducibility: ok'
