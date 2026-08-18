#!/bin/sh

set -eu

die() {
	printf '%s\n' "df mise fetch: $*" >&2
	exit 1
}

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
dist=${DF_RUNTIME_DIST:-$root/dist/runtime}
target=${1:-}

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

fetch_one() {
	platform=$1
	expected=$(awk -F '\t' -v platform="$platform" '$1 == platform { print $2 }' "$root/runtime/mise-assets.tsv")
	url=$(awk -F '\t' -v platform="$platform" '$1 == platform { print $3 }' "$root/runtime/mise-assets.tsv")
	[ -n "$expected" ] || die "missing checksum metadata: $platform"
	[ -n "$url" ] || die "missing URL metadata: $platform"

	download_dir=$dist/downloads
	archive=$download_dir/mise-$platform.tar.xz
	mkdir -p "$download_dir"
	download=true
	if [ -f "$archive" ]; then
		actual=$(sha256_file "$archive")
		[ "$actual" = "$expected" ] && download=false
	fi
	if [ "$download" = true ]; then
		temporary=$archive.part.$$
		trap 'rm -f "$temporary"' EXIT HUP INT TERM
		curl -fL --retry 3 --output "$temporary" "$url"
		actual=$(sha256_file "$temporary")
		[ "$actual" = "$expected" ] || die "download checksum mismatch: $platform"
		mv "$temporary" "$archive"
		trap - EXIT HUP INT TERM
	fi
	actual=$(sha256_file "$archive")
	[ "$actual" = "$expected" ] || die "cached checksum mismatch: $platform"

	stage=$(mktemp -d "$dist/.mise-$platform.XXXXXX")
	trap 'rm -rf "$stage"' EXIT HUP INT TERM
	tar -xJf "$archive" -C "$stage"
	binary=$(find "$stage" -type f -name mise -print | sed -n '1p')
	[ -n "$binary" ] || die "mise binary is missing from archive: $platform"
	output_dir=$dist/bin/$platform
	mkdir -p "$output_dir"
	temporary=$(mktemp "$output_dir/mise.part.XXXXXX")
	cp "$binary" "$temporary"
	chmod 0755 "$temporary"
	mv "$temporary" "$output_dir/mise"
	rm -rf "$stage"
	trap - EXIT HUP INT TERM
}

case "$target" in
all)
	tab=$(printf '\t')
	while IFS="$tab" read -r platform _checksum _url; do
		case "$platform" in '' | \#*) continue ;; esac
		fetch_one "$platform"
	done <"$root/runtime/mise-assets.tsv"
	;;
'') die 'usage: runtime/fetch-mise.sh <all|platform>' ;;
*) fetch_one "$target" ;;
esac

printf '%s\n' "$dist/bin"
