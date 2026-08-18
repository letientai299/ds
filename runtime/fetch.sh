#!/bin/sh

set -eu

die() {
	printf '%s\n' "df runtime fetch: $*" >&2
	exit 1
}

: "${DF_JANET_VERSION:?run through mise so DF_JANET_VERSION is set}"
: "${DF_JANET_SOURCE_SHA256:?run through mise so DF_JANET_SOURCE_SHA256 is set}"
: "${DF_JANET_HEADER_SHA256:?run through mise so DF_JANET_HEADER_SHA256 is set}"
: "${DF_JANET_SHELL_SHA256:?run through mise so DF_JANET_SHELL_SHA256 is set}"

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
source_dir=${DF_RUNTIME_DIST:-$root/dist/runtime}/src/janet-$DF_JANET_VERSION
base_url=https://github.com/janet-lang/janet/releases/download/v$DF_JANET_VERSION

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

fetch() {
	name=$1
	expected=$2
	destination=$source_dir/$name

	if [ -f "$destination" ]; then
		actual=$(sha256_file "$destination")
		[ "$actual" = "$expected" ] || die "cached checksum mismatch: $name"
		return
	fi

	temporary=$destination.part.$$
	trap 'rm -f "$temporary"' EXIT HUP INT TERM
	curl -fL --retry 3 --output "$temporary" "$base_url/$name"
	actual=$(sha256_file "$temporary")
	[ "$actual" = "$expected" ] || die "download checksum mismatch: $name"
	mv "$temporary" "$destination"
	trap - EXIT HUP INT TERM
}

mkdir -p "$source_dir"
fetch janet.c "$DF_JANET_SOURCE_SHA256"
fetch janet.h "$DF_JANET_HEADER_SHA256"
fetch shell.c "$DF_JANET_SHELL_SHA256"
printf '%s\n' "$source_dir"
