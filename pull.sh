#!/bin/sh

set -eu

die() {
	printf '%s\n' "df pull: $*" >&2
	exit 1
}

usage() {
	printf '%s\n' 'usage: pull.sh --url URL --manifest-sha256 HEX [--prefix DIR]'
}

url=
expected_manifest_sha256=
prefix=${XDG_DATA_HOME:-$HOME/.local/share}/df

while [ "$#" -gt 0 ]; do
	case "$1" in
	--url | --manifest-sha256 | --prefix)
		[ "$#" -ge 2 ] || die "$1 requires a value"
		case "$1" in
		--url) url=${2%/} ;;
		--manifest-sha256) expected_manifest_sha256=$2 ;;
		--prefix) prefix=$2 ;;
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

[ -n "$url" ] || die '--url is required'
[ -n "$expected_manifest_sha256" ] || die '--manifest-sha256 is required'
case "$expected_manifest_sha256" in
*[!0-9a-f]* | '') die 'manifest checksum must be lowercase hexadecimal' ;;
esac
[ "${#expected_manifest_sha256}" -eq 64 ] || die 'manifest checksum must contain 64 characters'

downloader=${DF_DOWNLOADER:-auto}
case "$downloader" in
auto)
	if command -v curl >/dev/null 2>&1; then
		downloader=curl
	elif command -v wget >/dev/null 2>&1; then
		downloader=wget
	else
		die 'curl or wget is required'
	fi
	;;
curl | wget) ;;
*) die "unsupported downloader: $downloader" ;;
esac

case "$downloader" in
curl)
	curl_command=${DF_CURL:-curl}
	command -v "$curl_command" >/dev/null 2>&1 || die "curl command is missing: $curl_command"
	download() { "$curl_command" -fsSL --retry 3 --output "$2" "$1"; }
	;;
wget)
	wget_command=${DF_WGET:-wget}
	command -v "$wget_command" >/dev/null 2>&1 || die "wget command is missing: $wget_command"
	download() { "$wget_command" -q -O "$2" "$1"; }
	;;
esac

if command -v sha256sum >/dev/null 2>&1; then
	checksum_kind=sha256sum
elif command -v shasum >/dev/null 2>&1; then
	checksum_kind=shasum
else
	checksum_kind=
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

source_dir=$prefix/incoming/pull-$$
mkdir -p "$source_dir/files"
download "$url/manifest.tsv" "$source_dir/manifest.tsv"
if [ -n "$checksum_kind" ]; then
	actual_manifest_sha256=$(sha256_file "$source_dir/manifest.tsv")
	[ "$actual_manifest_sha256" = "$expected_manifest_sha256" ] || die 'manifest checksum mismatch'
else
	printf '%s\n' 'df pull: warning: target has no SHA-256 utility; TLS verification is authoritative' >&2
fi

tab=$(printf '\t')
header_read=false
while IFS="$tab" read -r record mode expected_sha256 path extra; do
	[ -z "${extra:-}" ] || die 'manifest record has too many fields'
	case "$record" in
	df-bundle-v1)
		[ "$header_read" = false ] || die 'manifest has multiple headers'
		case "$mode" in '' | *[!0-9A-Za-z._-]*) die 'manifest version is unsafe' ;; esac
		header_read=true
		;;
	file)
		[ "$header_read" = true ] || die 'manifest header must be first'
		case "$mode" in 0644 | 0755) ;; *) die "invalid mode for $path" ;; esac
		case "$expected_sha256" in *[!0-9a-f]* | '') die "invalid checksum for $path" ;; esac
		[ "${#expected_sha256}" -eq 64 ] || die "invalid checksum length for $path"
		case "$path" in '' | /* | ../* | */../* | */..) die "unsafe bundle path: $path" ;; esac
		destination=$source_dir/files/$path
		mkdir -p "${destination%/*}"
		download "$url/files/$path" "$destination"
		chmod "$mode" "$destination"
		;;
	'') ;;
	*) die "unknown manifest record: $record" ;;
	esac
done <"$source_dir/manifest.tsv"

[ "$header_read" = true ] || die 'manifest header is missing'
[ -x "$source_dir/files/bootstrap.sh" ] || die 'verified bootstrap is missing'
"$source_dir/files/bootstrap.sh" \
	--source "$source_dir" \
	--prefix "$prefix" \
	--manifest-sha256 "$expected_manifest_sha256"
