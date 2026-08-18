#!/bin/sh

set -eu

die() {
	printf '%s\n' "ds controller: $*" >&2
	exit 1
}

usage() {
	printf '%s\n' 'usage: ds push HOST LAYER [--platform PLATFORM] [--prefix RELATIVE_PATH] [--home RELATIVE_PATH] [--dry-run|--deliver-only]'
}

root=$(dirname -- "$0")/../..
root=$(CDPATH='' cd "$root" && pwd)
runtime_dist=${DS_RUNTIME_DIST:-$root/dist/runtime}
ssh_command=${DS_SSH:-ssh}
host=${1:-}
layer=${2:-}
platform=
prefix=.local/share/ds
remote_home=
dry_run=false
deliver_only=false

[ -n "$host" ] || {
	usage
	die 'host is required'
}
[ -n "$layer" ] || {
	usage
	die 'layer is required'
}
shift 2

while [ "$#" -gt 0 ]; do
	case "$1" in
	--platform | --prefix | --home)
		[ "$#" -ge 2 ] || die "$1 requires a value"
		case "$1" in
		--platform) platform=$2 ;;
		--prefix) prefix=$2 ;;
		--home) remote_home=$2 ;;
		esac
		shift 2
		;;
	--dry-run)
		dry_run=true
		shift
		;;
	--deliver-only)
		deliver_only=true
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown argument: $1" ;;
	esac
done

case "$layer" in core | remote) ;; *) die "unknown layer: $layer" ;; esac
case "$host" in -*) die 'host must not begin with a hyphen' ;; esac
case "$prefix" in
'' | /* | ../* | */../* | */.. | *[!0-9A-Za-z._/-]*) die 'prefix must be a safe relative path' ;;
esac
case "$remote_home" in
'') ;;
/* | ../* | */../* | */.. | *[!0-9A-Za-z._/-]*) die 'home must be a safe relative path' ;;
esac
[ "$deliver_only" = false ] || [ "$dry_run" = false ] || die '--dry-run and --deliver-only are mutually exclusive'

if [ -z "$platform" ]; then
	probe=$("$ssh_command" "$host" 'uname -s; uname -m') || die 'remote platform probe failed; pass --platform'
	probe_os=$(printf '%s\n' "$probe" | sed -n '1p')
	probe_arch=$(printf '%s\n' "$probe" | sed -n '2p')
	case "$probe_os:$probe_arch" in
	Darwin:arm64) platform=macos-arm64 ;;
	Darwin:x86_64) platform=macos-x64 ;;
	Linux:aarch64 | Linux:arm64) platform=linux-arm64-musl ;;
	Linux:x86_64 | Linux:amd64) platform=linux-x64-musl ;;
	*) die "unsupported remote platform: $probe_os $probe_arch" ;;
	esac
fi

case "$platform" in
linux-arm64-musl | linux-x64-musl | macos-arm64 | macos-x64) ;;
*) die "unsupported platform: $platform" ;;
esac
janet=$runtime_dist/bin/$platform/janet
mise=$runtime_dist/bin/$platform/mise
[ -x "$janet" ] || die "Janet runtime is missing: $janet"
[ -x "$mise" ] || die "mise runtime is missing: $mise"

if command -v sha256sum >/dev/null 2>&1; then
	sha256_stream() { sha256sum | {
		read -r digest _rest
		printf '%s\n' "$digest"
	}; }
elif command -v shasum >/dev/null 2>&1; then
	sha256_stream() { shasum -a 256 | {
		read -r digest _rest
		printf '%s\n' "$digest"
	}; }
else
	die 'a SHA-256 utility is required'
fi

stage=$(mktemp -d "${TMPDIR:-/tmp}/ds-controller.XXXXXX")
trap 'rm -rf "$stage"' EXIT HUP INT TERM
snapshot=$stage/snapshot
"$root/src/bundle/build.sh" \
	--version content \
	--platform "$platform" \
	--janet "$janet" \
	--mise "$mise" \
	--output "$snapshot" >/dev/null
content_sha=$(sed -n '2,$p' "$snapshot/manifest.tsv" | sha256_stream)
version=ds-$(printf '%s\n' "$content_sha" | cut -c 1-16)
tab=$(printf '\t')
temporary_manifest=$snapshot/manifest.tsv.part
printf 'ds-bundle-v1%s%s\n' "$tab" "$version" >"$temporary_manifest"
sed -n '2,$p' "$snapshot/manifest.tsv" >>"$temporary_manifest"
mv "$temporary_manifest" "$snapshot/manifest.tsv"
sha256_stream <"$snapshot/manifest.tsv" >"$snapshot/manifest.sha256"

installed=$("$root/src/bundle/push.sh" \
	--snapshot "$snapshot" \
	--host "$host" \
	--prefix "$prefix")

if [ "$deliver_only" = false ]; then
	apply_args=$layer
	[ "$dry_run" = false ] || apply_args="$apply_args --dry-run"
	if [ -n "$remote_home" ]; then
		target_home=\$HOME/$remote_home
	else
		target_home=\$HOME
	fi
	"$ssh_command" "$host" \
		"mkdir -p \"$target_home\"; HOME=\"$target_home\" XDG_CACHE_HOME=\"$target_home/.cache\" XDG_CONFIG_HOME=\"$target_home/.config\" XDG_DATA_HOME=\"$target_home/.local/share\" XDG_STATE_HOME=\"$target_home/.local/state\" MISE_CACHE_DIR=\"$target_home/.cache/mise\" MISE_CONFIG_DIR=\"$target_home/.config/ds/mise\" MISE_DATA_DIR=\"$target_home/.local/share/mise\" MISE_STATE_DIR=\"$target_home/.local/state/mise\" \"$installed/ds\" apply $apply_args" >&2
fi

printf '%s\n' "$installed"
