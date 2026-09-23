#!/bin/sh

set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-build-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM

fail() {
	printf '%s\n' "runtime build: $*" >&2
	exit 1
}

mkdir -p "$work/bin" "$work/tmp" "$work/runtime/src/janet-test"
for source in janet.c janet.h shell.c; do
	: >"$work/runtime/src/janet-test/$source"
done

cat >"$work/bin/clang" <<'SH'
#!/bin/sh
set -eu
normalizer=false
output=
while [ "$#" -gt 0 ]; do
	case "$1" in
	*/normalize-macho.c) normalizer=true ;;
	-o) shift; output=$1 ;;
	esac
	shift
done
if [ "$normalizer" = true ]; then
	printf '%s\n' normalizer >>"$DS_BUILD_LOG"
	[ "${DS_FAIL_BUILD:-false}" = false ] || exit 7
fi
printf '%s\n' '#!/bin/sh' 'exit 0' >"$output"
chmod 0755 "$output"
SH

cat >"$work/bin/docker" <<'SH'
#!/bin/sh
set -eu
while [ "$#" -gt 0 ]; do
	if [ "$1" = --output ]; then
		shift
		printf '%s\n' fixture >"${1#type=local,dest=}/janet"
	fi
	shift
done
SH

for command in strip codesign; do
	printf '%s\n' '#!/bin/sh' 'exit 0' >"$work/bin/$command"
done
chmod 0755 "$work/bin/"*
export PATH="$work/bin:$PATH" TMPDIR="$work/tmp"
export DS_RUNTIME_DIST="$work/runtime" DS_JANET_VERSION=test
export DS_BUILD_LOG="$work/compiler.log"

"$root/src/runtime/build.sh" all >/dev/null
[ "$(cat "$DS_BUILD_LOG")" = normalizer ] || fail 'normalizer compiled more than once'
[ -z "$(find "$work/tmp" -mindepth 1 -print)" ] || fail 'successful build leaked scratch files'
for platform in macos-arm64 macos-x64 linux-arm64-musl linux-x64-musl; do
	[ -x "$DS_RUNTIME_DIST/bin/$platform/janet" ] || fail "missing runtime: $platform"
done

if DS_FAIL_BUILD=true "$root/src/runtime/build.sh" macos-arm64 >/dev/null; then
	fail 'compiler failure was ignored'
fi
[ -z "$(find "$work/tmp" -mindepth 1 -print)" ] || fail 'failed build leaked scratch files'
[ -z "$(find "$work/runtime" -name '*.part.*' -print)" ] || fail 'failed build leaked partial runtime'

printf '%s\n' 'runtime build: ok'
