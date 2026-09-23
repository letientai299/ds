#!/bin/sh

set -eu

die() {
	printf '%s\n' "ds runtime build: $*" >&2
	exit 1
}

: "${DS_JANET_VERSION:?run through mise so DS_JANET_VERSION is set}"

root=$(dirname -- "$0")/../..
root=$(CDPATH='' cd "$root" && pwd)
dist=${DS_RUNTIME_DIST:-$root/dist/runtime}
source_dir=$dist/src/janet-$DS_JANET_VERSION
target=${1:-}

[ -f "$source_dir/janet.c" ] || die 'Janet source is missing; run runtime/fetch.sh first'
[ -f "$source_dir/janet.h" ] || die 'Janet header is missing; run runtime/fetch.sh first'
[ -f "$source_dir/shell.c" ] || die 'Janet shell source is missing; run runtime/fetch.sh first'

# Reuse the host compiler helper across targets.
normalizer_path=
normalizer_dir=
temporary=
stage=
cleanup() {
	[ -z "$temporary" ] || rm -f "$temporary"
	[ -z "$stage" ] || rm -rf "$stage"
	[ -z "$normalizer_dir" ] || rm -rf "$normalizer_dir"
}
trap cleanup EXIT
trap 'exit 143' HUP INT TERM

normalize_macho() {
	if [ -z "$normalizer_path" ]; then
		normalizer_dir=$(mktemp -d "${TMPDIR:-/tmp}/ds-runtime-build.XXXXXX")
		normalizer_path=$normalizer_dir/normalize-macho
		clang -std=c99 -Wall -Wextra -Werror \
			"$root/src/runtime/normalize-macho.c" -o "$normalizer_path" >&2
	fi
}

build_macos() {
	platform=$1
	case "$platform" in
	macos-arm64) architecture=arm64 ;;
	macos-x64) architecture=x86_64 ;;
	*) die "invalid macOS platform: $platform" ;;
	esac

	command -v clang >/dev/null 2>&1 || die 'clang is required for macOS runtime builds'
	command -v codesign >/dev/null 2>&1 || die 'codesign is required for macOS runtime builds'
	command -v shasum >/dev/null 2>&1 || die 'shasum is required for deterministic macOS UUIDs'
	output_dir=$dist/bin/$platform
	mkdir -p "$output_dir"
	# janet.part stays inside the artifact directory so publishing is a
	# same-filesystem rename; the host-arch normalizer has no such need.
	temporary=$(mktemp "$output_dir/janet.part.XXXXXX")
	normalize_macho
	clang -std=c99 -O2 -DNDEBUG -DJANET_NO_DYNAMIC_MODULES \
		-I"$source_dir" -arch "$architecture" -mmacosx-version-min=12.0 \
		"$source_dir/janet.c" "$source_dir/shell.c" -lm -o "$temporary"
	strip -x "$temporary"
	uuid=$(printf '%s' "janet-$DS_JANET_VERSION-$platform" | shasum -a 256 | awk '{print substr($1, 1, 32)}')
	"$normalizer_path" "$temporary" "$uuid"
	codesign --force --sign - --identifier org.janet-lang.janet --timestamp=none "$temporary"
	chmod 0755 "$temporary"
	mv "$temporary" "$output_dir/janet"
	temporary=
}

build_linux() {
	platform=$1
	case "$platform" in
	linux-arm64-musl) docker_platform=linux/arm64 ;;
	linux-x64-musl) docker_platform=linux/amd64 ;;
	*) die "invalid Linux platform: $platform" ;;
	esac

	command -v docker >/dev/null 2>&1 || die 'Docker with Buildx is required for Linux runtime builds'
	output_dir=$dist/bin/$platform
	stage=$(mktemp -d "$dist/.build-$platform.XXXXXX")
	# Without this the second reproducibility pass is served entirely from the
	# BuildKit cache and the comparison comes out equal by construction.
	# shellcheck disable=SC2086 # DS_RUNTIME_BUILD_FLAGS is an intentional word list.
	docker buildx build \
		--platform "$docker_platform" \
		--file "$root/src/runtime/Dockerfile" \
		--output "type=local,dest=$stage" \
		${DS_RUNTIME_BUILD_FLAGS:-} \
		"$source_dir"
	mkdir -p "$output_dir"
	chmod 0755 "$stage/janet"
	mv "$stage/janet" "$output_dir/janet"
	rm -rf "$stage"
	stage=
}

build_one() {
	case "$1" in
	macos-arm64 | macos-x64) build_macos "$1" ;;
	linux-arm64-musl | linux-x64-musl) build_linux "$1" ;;
	*) die "unsupported platform: $1" ;;
	esac
}

case "$target" in
all)
	build_one macos-arm64
	build_one macos-x64
	build_one linux-arm64-musl
	build_one linux-x64-musl
	;;
'') die 'usage: runtime/build.sh <all|platform>' ;;
*) build_one "$target" ;;
esac

printf '%s\n' "$dist/bin"
