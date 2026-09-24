#!/bin/sh

set -eu

die() {
	printf '%s\n' "ds install: $*" >&2
	exit 1
}

usage() {
	printf '%s\n' 'usage: install.sh [--layer LAYER] [--version TAG] [--platform PLATFORM] [--prefix DIR] [--no-apply]'
}

repository=${DS_REPOSITORY:-letientai299/ds}
version=${DS_VERSION:-latest}
release_url=${DS_RELEASE_URL:-}
platform=${DS_PLATFORM:-}
prefix=${DS_PREFIX:-${XDG_DATA_HOME:-$HOME/.local/share}/ds}
layer=${DS_LAYER:-core}
apply=true

while [ "$#" -gt 0 ]; do
	case "$1" in
	--layer | --version | --platform | --prefix | --repository | --release-url)
		[ "$#" -ge 2 ] || die "$1 requires a value"
		case "$1" in
		--layer) layer=$2 ;;
		--version) version=$2 ;;
		--platform) platform=$2 ;;
		--prefix) prefix=$2 ;;
		--repository) repository=$2 ;;
		--release-url) release_url=$2 ;;
		esac
		shift 2
		;;
	--no-apply)
		apply=false
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown argument: $1" ;;
	esac
done

case "$layer" in core | remote | extra | ui | all) ;; *) die "unknown layer: $layer" ;; esac

if [ -z "$platform" ]; then
	operating_system=$(uname -s)
	architecture=$(uname -m)
	case "$operating_system:$architecture" in
	Darwin:arm64) platform=macos-arm64 ;;
	Darwin:x86_64) platform=macos-x64 ;;
	Linux:aarch64 | Linux:arm64) platform=linux-arm64-musl ;;
	Linux:x86_64 | Linux:amd64) platform=linux-x64-musl ;;
	*) die "unsupported platform: $operating_system $architecture; pass --platform" ;;
	esac
fi
case "$platform" in
linux-arm64-musl | linux-x64-musl | macos-arm64 | macos-x64) ;;
*) die "unsupported platform: $platform" ;;
esac

if [ -z "$release_url" ]; then
	# GitHub resolves `releases/latest/download` without an API call, so the
	# installer needs no token, no jq, and no knowledge of the current tag.
	case "$version" in
	latest) release_url=https://github.com/$repository/releases/latest/download ;;
	*) release_url=https://github.com/$repository/releases/download/$version ;;
	esac
fi

if command -v curl >/dev/null 2>&1; then
	download() { curl -fsSL --retry 3 --output "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
	download() { wget -q -O "$2" "$1"; }
else
	die 'curl or wget is required'
fi

if command -v sha256sum >/dev/null 2>&1; then
	sha256_file() {
		sha256sum "$1" | {
			read -r digest _rest
			printf '%s\n' "$digest"
		}
	}
elif command -v shasum >/dev/null 2>&1; then
	sha256_file() {
		shasum -a 256 "$1" | {
			read -r digest _rest
			printf '%s\n' "$digest"
		}
	}
else
	sha256_file() { printf '%s\n' ''; }
fi

command -v tar >/dev/null 2>&1 || die 'tar is required'

work=$(mktemp -d "${TMPDIR:-/tmp}/ds-install.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

archive_name=ds-$platform.tar.gz
download "$release_url/$archive_name" "$work/$archive_name"
if download "$release_url/$archive_name.sha256" "$work/$archive_name.sha256" 2>/dev/null; then
	expected=$(sed -n '1p' "$work/$archive_name.sha256" | cut -d ' ' -f 1)
	actual=$(sha256_file "$work/$archive_name")
	if [ -z "$actual" ]; then
		printf '%s\n' 'ds install: warning: no SHA-256 utility; TLS verification is authoritative' >&2
	else
		[ "$actual" = "$expected" ] || die 'release archive checksum mismatch'
	fi
else
	printf '%s\n' 'ds install: warning: release checksum is unavailable; TLS verification is authoritative' >&2
fi

mkdir -p "$work/extract"
tar -xzf "$work/$archive_name" -C "$work/extract"
snapshot=
for candidate in "$work"/extract/*; do
	[ -d "$candidate" ] || continue
	[ -z "$snapshot" ] || die 'release archive contains more than one snapshot'
	snapshot=$candidate
done
[ -n "$snapshot" ] || die 'release archive contains no snapshot'
[ -x "$snapshot/bootstrap.sh" ] || die 'release archive has no bootstrap entrypoint'

manifest_sha=$(sed -n '1p' "$snapshot/manifest.sha256")
snapshot_version=$(
	"$snapshot/bootstrap.sh" \
		--source "$snapshot" \
		--manifest-sha256 "$manifest_sha" \
		--verify-only
)
# Version directories are immutable, so reinstalling the same release is a
# no-op rather than an error.
if [ -x "$prefix/versions/$snapshot_version/ds" ]; then
	installed=$prefix/versions/$snapshot_version
else
	installed=$(
		"$snapshot/bootstrap.sh" \
			--source "$snapshot" \
			--prefix "$prefix" \
			--manifest-sha256 "$manifest_sha"
	)
fi

if [ "$apply" = false ]; then
	printf '%s\n' "$installed"
	exit 0
fi

"$installed/ds" apply "$layer"
printf '%s\n' "$installed"
