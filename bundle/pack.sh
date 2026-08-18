#!/bin/sh

set -eu

die() {
	printf '%s\n' "df pack: $*" >&2
	exit 1
}

usage() {
	printf '%s\n' 'usage: bundle/pack.sh --snapshot DIR --output FILE'
}

root=$(dirname -- "$0")/..
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

manifest_sha=$(sed -n '1p' "$snapshot/manifest.sha256")
version=$(
	"$root/bootstrap.sh" \
		--source "$snapshot" \
		--manifest-sha256 "$manifest_sha" \
		--verify-only
)

stage=$(mktemp -d "${TMPDIR:-/tmp}/df-pack.XXXXXX")
temporary_tar=$stage/bundle.tar
temporary_output=$output.part.$$
trap 'rm -rf "$stage"; rm -f "$temporary_output"' EXIT HUP INT TERM
bundle_name=df-$version
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
