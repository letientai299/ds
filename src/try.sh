#!/bin/sh

set -eu

die() {
	printf '%s\n' "ds try: $*" >&2
	exit 1
}

usage() {
	printf '%s\n' 'usage: try.sh [--layer core|remote] [--source auto|checkout|release] [--version TAG] [--image IMAGE] [--platform DOCKER_PLATFORM] [--command COMMAND]'
}

repository=${DS_REPOSITORY:-letientai299/ds}
version=${DS_VERSION:-latest}
layer=core
source_mode=auto
image=${DS_TRY_IMAGE:-ubuntu:24.04}
docker_platform=
command_line=

while [ "$#" -gt 0 ]; do
	case "$1" in
	--layer | --source | --version | --image | --platform | --command | --repository)
		[ "$#" -ge 2 ] || die "$1 requires a value"
		case "$1" in
		--layer) layer=$2 ;;
		--source) source_mode=$2 ;;
		--version) version=$2 ;;
		--image) image=$2 ;;
		--platform) docker_platform=$2 ;;
		--command) command_line=$2 ;;
		--repository) repository=$2 ;;
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

case "$layer" in core | remote) ;; *) die "unknown layer: $layer" ;; esac
case "$source_mode" in auto | checkout | release) ;; *) die "unknown source: $source_mode" ;; esac
command -v docker >/dev/null 2>&1 || die 'Docker is required'

# The script is also served over curl, where $0 says nothing about a checkout.
root=
script_dir=$(dirname -- "$0" 2>/dev/null || true)
if [ -n "$script_dir" ] && [ -d "$script_dir" ]; then
	candidate=$(CDPATH='' cd "$script_dir/.." 2>/dev/null && pwd) || candidate=
	[ -z "$candidate" ] || [ ! -x "$candidate/src/bundle/build.sh" ] || root=$candidate
fi

if [ -z "$docker_platform" ]; then
	case "$(uname -m)" in
	aarch64 | arm64) docker_platform=linux/arm64 ;;
	x86_64 | amd64) docker_platform=linux/amd64 ;;
	*) die "unsupported host architecture: $(uname -m)" ;;
	esac
fi
case "$docker_platform" in
linux/arm64 | linux/arm64/v8) platform=linux-arm64-musl ;;
linux/amd64) platform=linux-x64-musl ;;
*) die "unsupported Docker platform: $docker_platform" ;;
esac

runtime_dist=${DS_RUNTIME_DIST:-${root:-.}/dist/runtime}
if [ "$source_mode" = auto ]; then
	if [ -n "$root" ] && [ -x "$runtime_dist/bin/$platform/janet" ] &&
		[ -x "$runtime_dist/bin/$platform/mise" ]; then
		source_mode=checkout
	else
		source_mode=release
	fi
fi

# Without --command the container hands over an interactive login Zsh, which is
# the point of the demo: the managed .zshrc marker loads the same environment a
# real target gets.
if [ -z "$command_line" ]; then
	command_line='exec zsh -l'
	interactive='--interactive --tty'
else
	interactive=
fi

install_curl='
    if ! command -v curl >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq && apt-get install -y -qq curl ca-certificates >/dev/null
        elif command -v apk >/dev/null 2>&1; then
            apk add --no-cache curl ca-certificates >/dev/null
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y -q curl ca-certificates >/dev/null
        else
            printf "%s\n" "ds try: no supported package manager for curl" >&2
            exit 1
        fi
    fi
'

if [ "$source_mode" = release ]; then
	case "$version" in
	latest) release_url=https://github.com/$repository/releases/latest/download ;;
	*) release_url=https://github.com/$repository/releases/download/$version ;;
	esac
	printf '%s\n' "ds try: applying $layer from $release_url in a throwaway $image container" >&2
	# shellcheck disable=SC2086 # $interactive is a deliberate word-split flag pair.
	exec docker run --rm $interactive \
		--platform "$docker_platform" \
		--env HOME=/root \
		--env DEBIAN_FRONTEND=noninteractive \
		--env "TERM=${TERM:-xterm-256color}" \
		"$image" /bin/sh -c "$install_curl"'
        set -eu
        # Downloading first rather than piping into sh, so that a failed fetch
        # is an error instead of an empty script that silently succeeds.
        curl -fsSL --output /tmp/ds-install.sh "$1/install.sh"
        sh /tmp/ds-install.sh --layer "$2" --release-url "$1"
        eval "$3"
    ' ds-try "$release_url" "$layer" "$command_line"
fi

[ -n "$root" ] || die 'checkout source requires running this script from a checkout'
janet=$runtime_dist/bin/$platform/janet
mise=$runtime_dist/bin/$platform/mise
[ -x "$janet" ] || die "Janet runtime is missing: $janet; run mise run runtime:build"
[ -x "$mise" ] || die "mise runtime is missing: $mise; run mise run runtime:fetch-mise"

work=$(mktemp -d "${TMPDIR:-/tmp}/ds-try.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM
snapshot=$work/snapshot
"$root/src/bundle/build.sh" \
	--version try \
	--platform "$platform" \
	--janet "$janet" \
	--mise "$mise" \
	--output "$snapshot" >/dev/null
manifest_sha=$(sed -n '1p' "$snapshot/manifest.sha256")

printf '%s\n' "ds try: applying $layer from this checkout in a throwaway $image container" >&2

# shellcheck disable=SC2086 # $interactive is a deliberate word-split flag pair.
docker run --rm $interactive \
	--platform "$docker_platform" \
	--volume "$snapshot:/snapshot:ro" \
	--env HOME=/root \
	--env DEBIAN_FRONTEND=noninteractive \
	--env "TERM=${TERM:-xterm-256color}" \
	"$image" /bin/sh -c '
        set -eu
        installed=$(/snapshot/bootstrap.sh \
            --source /snapshot \
            --prefix "$HOME/.local/share/ds" \
            --manifest-sha256 "$1")
        "$installed/ds" apply "$2"
        "$installed/ds" status "$2"
        eval "$3"
    ' ds-try "$manifest_sha" "$layer" "$command_line"
