#!/bin/sh

set -eu

die() {
	printf '%s\n' "ds runtime fetch: $*" >&2
	exit 1
}

: "${DS_JANET_VERSION:?run through mise so DS_JANET_VERSION is set}"
: "${DS_JANET_SOURCE_SHA256:?run through mise so DS_JANET_SOURCE_SHA256 is set}"
: "${DS_JANET_HEADER_SHA256:?run through mise so DS_JANET_HEADER_SHA256 is set}"
: "${DS_JANET_SHELL_SHA256:?run through mise so DS_JANET_SHELL_SHA256 is set}"

root=$(dirname -- "$0")/../..
root=$(CDPATH='' cd "$root" && pwd)
source_dir=${DS_RUNTIME_DIST:-$root/dist/runtime}/src/janet-$DS_JANET_VERSION
base_url=https://github.com/janet-lang/janet/releases/download/v$DS_JANET_VERSION

# shellcheck source=src/lib/checksum.sh
. "$root/src/lib/checksum.sh"

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
fetch janet.c "$DS_JANET_SOURCE_SHA256"
fetch janet.h "$DS_JANET_HEADER_SHA256"
fetch shell.c "$DS_JANET_SHELL_SHA256"
printf '%s\n' "$source_dir"
