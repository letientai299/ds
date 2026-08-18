#!/bin/sh

set -eu

die() {
	printf '%s\n' "ds runtime verify: $*" >&2
	exit 1
}

: "${DS_JANET_VERSION:?run through mise so DS_JANET_VERSION is set}"
: "${DS_MISE_VERSION:?run through mise so DS_MISE_VERSION is set}"
: "${DS_ALPINE_IMAGE:?run through mise so DS_ALPINE_IMAGE is set}"
: "${DS_UBUNTU_IMAGE:?run through mise so DS_UBUNTU_IMAGE is set}"

root=$(dirname -- "$0")/../..
root=$(CDPATH='' cd "$root" && pwd)
dist=${DS_RUNTIME_DIST:-$root/dist/runtime}
target=${1:-}
expected_version=$DS_JANET_VERSION

assert_runtime_contract() {
	binary=$1
	version=$("$binary" --version)
	ffi=$("$binary" -e '(print (has-key? (curenv) (quote ffi)))')
	dynamic=$("$binary" -e '(try (native "missing") ([_err] (print _err)))')
	case "$version" in "$expected_version"-*) ;; *) die "unexpected Janet version: $version" ;; esac
	[ "$ffi" = false ] || die 'FFI is enabled'
	case "$dynamic" in *'dynamic modules not supported'*) ;; *) die 'dynamic modules are enabled' ;; esac
}

verify_macos() {
	platform=$1
	binary=$dist/bin/$platform/janet
	mise_binary=$dist/bin/$platform/mise
	[ -x "$binary" ] || die "runtime is missing: $platform"
	[ -x "$mise_binary" ] || die "mise is missing: $platform"
	case "$platform" in
	macos-arm64)
		file "$binary" | grep -q 'Mach-O 64-bit executable arm64' || die 'invalid macOS ARM64 binary'
		assert_runtime_contract "$binary"
		;;
	macos-x64)
		file "$binary" | grep -q 'Mach-O 64-bit executable x86_64' || die 'invalid macOS x64 binary'
		assert_runtime_contract "$binary"
		;;
	esac
	dependencies=$(otool -L "$binary")
	printf '%s\n' "$dependencies" | grep -q '/usr/lib/libSystem.B.dylib' || die 'macOS runtime does not use libSystem'
	[ "$(printf '%s\n' "$dependencies" | grep -c '^\t/')" -eq 1 ] || die 'macOS runtime has unexpected dynamic libraries'
	otool -l "$binary" | grep -q LC_UUID || die 'macOS runtime is missing LC_UUID'
	codesign --verify --strict "$binary" 2>/dev/null || die 'macOS runtime signature is invalid'
	case "$platform" in
	macos-arm64) mise_version=$("$mise_binary" --version) ;;
	macos-x64) mise_version=$("$mise_binary" --version) ;;
	esac
	case "$mise_version" in "$DS_MISE_VERSION"*) ;; *) die "unexpected mise version: $mise_version" ;; esac
}

verify_linux_in() {
	binary=$1
	mise_binary=$2
	docker_platform=$3
	image=$4
	docker run --rm --platform "$docker_platform" --volume "$binary:/janet:ro" "$image" /janet --version |
		grep -q "^$expected_version-" || die "runtime failed in $image"
	docker run --rm --platform "$docker_platform" --volume "$binary:/janet:ro" "$image" \
		/janet -e '(print (has-key? (curenv) (quote ffi)))' |
		grep -q '^false$' || die "FFI is enabled in $image"
	docker run --rm --platform "$docker_platform" --volume "$mise_binary:/mise:ro" "$image" /mise --version |
		grep -q "^$DS_MISE_VERSION" || die "mise failed in $image"
}

verify_linux() {
	platform=$1
	binary=$dist/bin/$platform/janet
	mise_binary=$dist/bin/$platform/mise
	[ -x "$binary" ] || die "runtime is missing: $platform"
	[ -x "$mise_binary" ] || die "mise is missing: $platform"
	file "$binary" | grep -Eq 'static(ally|-pie)? linked' || die "runtime is dynamically linked: $platform"
	file "$mise_binary" | grep -Eq 'static(ally|-pie)? linked' || die "mise is dynamically linked: $platform"
	case "$platform" in
	linux-arm64-musl)
		file "$binary" | grep -Eq 'ARM aarch64|ARM64' || die 'invalid Linux ARM64 binary'
		docker_platform=linux/arm64
		;;
	linux-x64-musl)
		file "$binary" | grep -q 'x86-64' || die 'invalid Linux x64 binary'
		docker_platform=linux/amd64
		;;
	esac
	verify_linux_in "$binary" "$mise_binary" "$docker_platform" "$DS_ALPINE_IMAGE"
	verify_linux_in "$binary" "$mise_binary" "$docker_platform" "$DS_UBUNTU_IMAGE"
}

verify_one() {
	case "$1" in
	macos-arm64 | macos-x64) verify_macos "$1" ;;
	linux-arm64-musl | linux-x64-musl) verify_linux "$1" ;;
	*) die "unsupported platform: $1" ;;
	esac
}

case "$target" in
all)
	verify_one macos-arm64
	verify_one macos-x64
	verify_one linux-arm64-musl
	verify_one linux-x64-musl
	;;
'') die 'usage: runtime/verify.sh <all|platform>' ;;
*) verify_one "$target" ;;
esac

printf '%s\n' 'runtime matrix: ok'
