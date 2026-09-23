#!/bin/sh
set -eu

die() {
	printf '%s\n' "ds docker: $*" >&2
	exit 1
}

rebuild=false
while [ "$#" -gt 0 ]; do
	case "$1" in
	--rebuild)
		rebuild=true
		shift
		;;
	-h | --help)
		printf '%s\n' 'usage: ds docker [--rebuild] [-- COMMAND [ARG...]]' \
			'Cached Ubuntu core shell; current directory mounts at /work.' \
			'--rebuild refreshes Ubuntu, packages, and checkout configuration.'
		exit 0
		;;
	--)
		shift
		break
		;;
	*) die "unknown argument: $1" ;;
	esac
done

command -v docker >/dev/null 2>&1 || die 'Docker is required'
engine=$(docker info --format '{{.OSType}}/{{.Architecture}}') || die 'Docker engine is unavailable'
case "$engine" in
linux/aarch64 | linux/arm64)
	architecture=arm64
	platform=linux-arm64-musl
	;;
linux/x86_64 | linux/amd64)
	architecture=amd64
	platform=linux-x64-musl
	;;
*) die "unsupported Docker engine: $engine" ;;
esac
image=${DS_DOCKER_IMAGE:-ds-local:core-$architecture}
root=$(CDPATH='' cd "$(dirname -- "$0")/../.." && pwd)

build_image() (
	runtime=${DS_RUNTIME_DIST:-$root/dist/runtime}/bin/$platform
	[ -x "$runtime/janet" ] || die 'run mise run runtime:build first'
	[ -x "$runtime/mise" ] || die 'run mise run runtime:fetch-mise first'
	work=$(mktemp -d "${TMPDIR:-/tmp}/ds-docker.XXXXXX")
	trap 'rm -rf "$work"' EXIT
	trap 'exit 143' HUP INT TERM
	"$root/src/bundle/build.sh" --version docker --platform "$platform" \
		--janet "$runtime/janet" --mise "$runtime/mise" \
		--output "$work/snapshot" >/dev/null
	cp "$root/src/bundle/Dockerfile" "$work/Dockerfile"
	printf '%s\n' "ds docker: building $image from ubuntu:latest" >&2
	docker build --pull --no-cache --platform "linux/$architecture" \
		--tag "$image" "$work"
)

if [ "$rebuild" = true ] || ! docker image inspect "$image" >/dev/null 2>&1; then
	build_image
fi

# Quote Docker's CSV mount syntax.
mount_source=$(pwd -P | sed 's/"/""/g')
if [ -t 0 ] && [ -t 1 ]; then
	set -- --tty "$image" "$@"
else
	set -- "$image" "$@"
fi
exec docker run --rm --init --interactive --pull never \
	--platform "linux/$architecture" \
	--mount "type=bind,\"source=$mount_source\",target=/work" \
	--workdir /work --env TERM=xterm-256color \
	--env LANG=C.UTF-8 --env LC_ALL=C.UTF-8 "$@"
