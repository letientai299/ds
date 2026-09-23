#!/bin/sh

set -eu

# `touch -t` interprets its stamp in the caller's local timezone, so an
# unpinned TZ makes the normalized mtimes -- and therefore the archive digest
# -- depend on where the release was built.
export TZ=UTC0

die() {
	printf '%s\n' "ds pack: $*" >&2
	exit 1
}

usage() {
	printf '%s\n' 'usage: src/bundle/pack.sh --snapshot DIR --output FILE'
}

root=$(dirname -- "$0")/../..
root=$(CDPATH='' cd "$root" && pwd)
snapshot=
output=

while [ "$#" -gt 0 ]; do
	case "$1" in
	--snapshot | --output)
		[ "$#" -ge 2 ] || die "$1 requires a value"
		case "$1" in
		--snapshot) snapshot=$2 ;;
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

[ -n "$snapshot" ] || die '--snapshot is required'
[ -d "$snapshot" ] || die "snapshot is missing: $snapshot"
snapshot=$(CDPATH='' cd "$snapshot" && pwd)
[ -n "$output" ] || die '--output is required'
case "$output" in /*) ;; *) output=$PWD/$output ;; esac
[ ! -e "$output" ] || die "output already exists: $output"
[ ! -e "$output.sha256" ] || die "checksum output already exists: $output.sha256"

# shellcheck source=src/lib/checksum.sh
. "$root/src/lib/checksum.sh"

manifest_sha=$(sed -n '1p' "$snapshot/manifest.sha256")
version=$(
	"$root/src/bootstrap.sh" \
		--source "$snapshot" \
		--manifest-sha256 "$manifest_sha" \
		--verify-only
)

stage=$(mktemp -d "${TMPDIR:-/tmp}/ds-pack.XXXXXX")
temporary_tar=$stage/bundle.tar
temporary_output=$output.part.$$
trap 'rm -rf "$stage"; rm -f "$temporary_output"' EXIT HUP INT TERM
bundle_name=ds-$version
mkdir -p "$stage/$bundle_name"
cp -R "$snapshot/." "$stage/$bundle_name/"
find "$stage/$bundle_name" -exec touch -t 198001010000 {} +
find "$stage/$bundle_name" ! -type d -print | sed "s#^$stage/##" | LC_ALL=C sort >"$stage/files.txt"
tar -cf "$temporary_tar" \
	--format ustar \
	--uid 0 --gid 0 --uname root --gname root \
	-C "$stage" -T "$stage/files.txt"
gzip -n -c "$temporary_tar" >"$temporary_output"
mv "$temporary_output" "$output"
sha256_file "$output" >"$output.sha256"
rm -rf "$stage"
trap - EXIT HUP INT TERM

printf '%s\n' "$output"
