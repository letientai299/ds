#!/bin/sh

set -eu

die() {
	printf '%s\n' "ds release: $*" >&2
	exit 1
}

usage() {
	printf '%s\n' 'usage: src/bundle/release.sh --version VERSION [--output DIR]'
}

root=$(dirname -- "$0")/../..
root=$(CDPATH='' cd "$root" && pwd)
version=
output=

while [ "$#" -gt 0 ]; do
	case "$1" in
	--version | --output)
		[ "$#" -ge 2 ] || die "$1 requires a value"
		case "$1" in
		--version) version=$2 ;;
		--output) output=$2 ;;
		esac
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown argument: $1" ;;
	esac
done

[ -n "$version" ] || die '--version is required'
case "$version" in *[!0-9A-Za-z._-]*) die 'version contains unsafe characters' ;; esac
output=${output:-$root/dist/release/$version}
case "$output" in /*) ;; *) output=$PWD/$output ;; esac

runtime_dist=${DS_RUNTIME_DIST:-$root/dist/runtime}
rm -rf "$output"
mkdir -p "$output"

# Asset names carry the platform but not the version so that
# `releases/latest/download/<asset>` resolves without an API call. See
# src/install.sh.
for platform in linux-arm64-musl linux-x64-musl macos-arm64 macos-x64; do
	janet=$runtime_dist/bin/$platform/janet
	mise=$runtime_dist/bin/$platform/mise
	[ -x "$janet" ] || die "Janet runtime is missing: $janet"
	[ -x "$mise" ] || die "mise runtime is missing: $mise"
	snapshot=$output/snapshot-$platform
	"$root/src/bundle/build.sh" \
		--version "$version" \
		--platform "$platform" \
		--janet "$janet" \
		--mise "$mise" \
		--output "$snapshot" >/dev/null
	"$root/src/bundle/pack.sh" \
		--snapshot "$snapshot" \
		--output "$output/ds-$platform.tar.gz" >/dev/null
	rm -rf "$snapshot"
done

cp "$root/src/install.sh" "$output/install.sh"
cp "$root/src/try.sh" "$output/try.sh"
printf '%s\n' "$output"
