#!/bin/sh

set -eu

die() {
	printf '%s\n' "ds bootstrap: $*" >&2
	exit 1
}

usage() {
	printf '%s\n' 'usage: src/bootstrap.sh --source DIR [--prefix DIR] --manifest-sha256 HEX [--verify-only]'
}

source_dir=
prefix=
expected_manifest_sha256=
verify_only=false

while [ "$#" -gt 0 ]; do
	case "$1" in
	--source)
		[ "$#" -ge 2 ] || die '--source requires a value'
		source_dir=$2
		shift 2
		;;
	--prefix)
		[ "$#" -ge 2 ] || die '--prefix requires a value'
		prefix=$2
		shift 2
		;;
	--manifest-sha256)
		[ "$#" -ge 2 ] || die '--manifest-sha256 requires a value'
		expected_manifest_sha256=$2
		shift 2
		;;
	--verify-only)
		verify_only=true
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown argument: $1" ;;
	esac
done

[ -n "$source_dir" ] || die '--source is required'
[ -n "$expected_manifest_sha256" ] || die '--manifest-sha256 is required'
[ "$verify_only" = true ] || [ -n "$prefix" ] || die '--prefix is required'
[ -f "$source_dir/manifest.tsv" ] || die 'manifest.tsv is missing'

case "$expected_manifest_sha256" in
*[!0-9a-f]* | '') die 'manifest checksum must be lowercase hexadecimal' ;;
esac
[ "${#expected_manifest_sha256}" -eq 64 ] || die 'manifest checksum must contain 64 characters'

checksum_kind=
if command -v sha256sum >/dev/null 2>&1; then
	checksum_kind=sha256sum
elif command -v shasum >/dev/null 2>&1; then
	checksum_kind=shasum
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

if [ -n "$checksum_kind" ]; then
	actual_manifest_sha256=$(sha256_file "$source_dir/manifest.tsv")
	[ "$actual_manifest_sha256" = "$expected_manifest_sha256" ] || die 'manifest checksum mismatch'
else
	printf '%s\n' 'ds bootstrap: warning: target has no SHA-256 utility; controller verification is authoritative' >&2
fi

tab=$(printf '\t')
header_read=false
version=
file_count=0

while IFS="$tab" read -r record field2 field3 field4 extra; do
	[ -z "${extra:-}" ] || die 'manifest record has too many fields'
	case "$record" in
	ds-bundle-v1)
		[ "$header_read" = false ] || die 'manifest has multiple headers'
		[ -n "$field2" ] || die 'manifest version is empty'
		[ -z "$field3$field4" ] || die 'manifest header has extra fields'
		case "$field2" in *[!0-9A-Za-z._-]*) die 'manifest version contains unsafe characters' ;; esac
		version=$field2
		header_read=true
		;;
	file)
		[ "$header_read" = true ] || die 'manifest header must be first'
		mode=$field2
		expected_sha256=$field3
		path=$field4
		case "$mode" in 0644 | 0755) ;; *) die "invalid mode for $path" ;; esac
		case "$expected_sha256" in *[!0-9a-f]* | '') die "invalid checksum for $path" ;; esac
		[ "${#expected_sha256}" -eq 64 ] || die "invalid checksum length for $path"
		case "$path" in '' | /* | ../* | */../* | */..) die "unsafe bundle path: $path" ;; esac
		[ -f "$source_dir/files/$path" ] || die "bundle file is missing: $path"
		if [ -n "$checksum_kind" ]; then
			actual_sha256=$(sha256_file "$source_dir/files/$path")
			[ "$actual_sha256" = "$expected_sha256" ] || die "checksum mismatch: $path"
		fi
		file_count=$((file_count + 1))
		;;
	'') ;;
	*) die "unknown manifest record: $record" ;;
	esac
done <"$source_dir/manifest.tsv"

[ "$header_read" = true ] || die 'manifest header is missing'
[ "$file_count" -gt 0 ] || die 'manifest contains no files'

if [ "$verify_only" = true ]; then
	printf '%s\n' "$version"
	exit 0
fi

install_root=$prefix/versions/$version
[ ! -e "$install_root" ] || die "version is already installed: $version"
mkdir -p "$install_root"

while IFS="$tab" read -r record mode _expected_sha256 path _extra; do
	[ "$record" = file ] || continue
	destination=$install_root/$path
	mkdir -p "${destination%/*}"
	cat "$source_dir/files/$path" >"$destination"
	chmod "$mode" "$destination"
done <"$source_dir/manifest.tsv"

printf '%s\n' "$prefix/versions/$version"
