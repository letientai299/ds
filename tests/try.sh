#!/bin/sh

set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-try-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM

fail() {
	printf '%s\n' "try test: $*" >&2
	exit 1
}

mkdir -p "$work/checkout/src/bundle" "$work/bin" "$work/tmp"
cp "$root/src/try.sh" "$work/checkout/src/try.sh"
cat >"$work/checkout/src/bundle/build.sh" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$@" >"$DS_BUILD_ARGS"
while [ "$#" -gt 0 ]; do
	if [ "$1" = --output ]; then
		mkdir -p "$2"
		printf '%s\n' fixture >"$2/manifest.sha256"
	fi
	shift
done
SH
cat >"$work/bin/docker" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$@" >"$DS_DOCKER_ARGS"
shift
snapshot=
while [ "$#" -gt 0 ]; do
	case "$1" in
	--rm | --interactive | --tty) shift ;;
	--volume) snapshot=${2%:/snapshot:ro}; shift 2 ;;
	--platform | --env) shift 2 ;;
	*) shift; break ;;
	esac
done
if [ -n "$snapshot" ]; then
	[ -f "$snapshot/manifest.sha256" ]
	exit "${DS_DOCKER_STATUS:-0}"
fi
exec "$@"
SH
cat >"$work/bin/sh" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >"$DS_INSTALL_ARGS"
SH
printf '%s\n' '#!/bin/sh' 'exit 0' >"$work/bin/curl"
chmod 0755 "$work/bin/"* "$work/checkout/src/bundle/build.sh"
export DS_BUILD_ARGS="$work/build.args" DS_DOCKER_ARGS="$work/docker.args"
export DS_INSTALL_ARGS="$work/install.args"
export PATH="$work/bin:$PATH" TMPDIR="$work/tmp"
export DS_RUNTIME_DIST="$work/checkout/dist/runtime"
for platform in linux-arm64-musl linux-x64-musl; do
	mkdir -p "$DS_RUNTIME_DIST/bin/$platform"
	for binary in janet mise; do
		printf '%s\n' '#!/bin/sh' 'exit 0' >"$DS_RUNTIME_DIST/bin/$platform/$binary"
		chmod 0755 "$DS_RUNTIME_DIST/bin/$platform/$binary"
	done
done

for architecture in amd64 arm64; do
	"$work/checkout/src/try.sh" --source checkout --platform "linux/$architecture" --command :
	platform=linux-arm64-musl
	[ "$architecture" != amd64 ] || platform=linux-x64-musl
	grep -qx "$platform" "$DS_BUILD_ARGS" || fail 'wrong snapshot architecture'
	grep -qx "linux/$architecture" "$DS_DOCKER_ARGS" || fail 'wrong container architecture'
	[ -z "$(find "$work/tmp" -mindepth 1 -print)" ] || fail 'successful demo leaked snapshot'
done

if DS_DOCKER_STATUS=9 "$work/checkout/src/try.sh" --source checkout --command :; then
	fail 'container failure was hidden'
fi
[ -z "$(find "$work/tmp" -mindepth 1 -print)" ] || fail 'failed demo leaked snapshot'

"$work/checkout/src/try.sh" --source release --version v-test --repository example/ds --command :
grep -qx -- '--release-url' "$DS_INSTALL_ARGS" || fail 'installer lost release URL'
grep -qx 'https://github.com/example/ds/releases/download/v-test' "$DS_INSTALL_ARGS" || fail 'installer lost requested version'

printf '%s\n' 'try: ok'
