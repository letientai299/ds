#!/bin/sh

set -eu

die() {
	printf '%s\n' "ds bundle: $*" >&2
	exit 1
}

usage() {
	printf '%s\n' 'usage: src/bundle/build.sh --version VERSION --platform PLATFORM --janet FILE --mise FILE --output DIR'
}

root=$(dirname -- "$0")/../..
root=$(CDPATH='' cd "$root" && pwd)
version=
platform=
janet=
mise=
output=

while [ "$#" -gt 0 ]; do
	case "$1" in
	--version | --platform | --janet | --mise | --output)
		[ "$#" -ge 2 ] || die "$1 requires a value"
		case "$1" in
		--version) version=$2 ;;
		--platform) platform=$2 ;;
		--janet) janet=$2 ;;
		--mise) mise=$2 ;;
		--output) output=$2 ;;
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

[ -n "$version" ] || die '--version is required'
case "$version" in *[!0-9A-Za-z._-]*) die 'version contains unsafe characters' ;; esac
case "$platform" in
linux-arm64-musl | linux-x64-musl | macos-arm64 | macos-x64) ;;
*) die "unsupported platform: $platform" ;;
esac
[ -x "$janet" ] || die 'Janet runtime is not executable'
[ -x "$mise" ] || die 'mise runtime is not executable'
[ -n "$output" ] || die '--output is required'
[ ! -e "$output" ] || die "output already exists: $output"

# shellcheck source=src/lib/checksum.sh
. "$root/src/lib/checksum.sh"

# A snapshot mirrors the checkout layout: the `ds` launcher at the root and
# every payload under `src/`, so DS_ROOT means the same thing in both.
files=$output/files
payload=$files/src
nvim_source=${DS_NVIM_SOURCE:-$root/../nvim.conf}
tmux_source=${DS_TMUX_SOURCE:-$root/../tmux.conf}
DS_MISE=${DS_GENERATOR_MISE:-mise} "$root/src/scripts/generate.sh" --check >/dev/null
mkdir -p "$payload/runtime/bin/$platform" "$payload/scripts" "$payload/mise" \
	"$payload/vendor/nvim.conf" "$payload/vendor/tmux.conf"
cp "$root/src/bootstrap.sh" "$output/bootstrap.sh"
cp "$root/src/bootstrap.sh" "$payload/bootstrap.sh"
cp "$root/ds" "$files/ds"
cp "$root/src/mise/mise.toml" "$payload/mise/mise.toml"
cp "$root/src/catalog.toml" "$payload/catalog.toml"
# MIT requires the notice to travel with the redistributed Janet and mise
# binaries, so it becomes a manifest entry like any other payload file.
cp "$root/src/THIRD-PARTY.md" "$payload/THIRD-PARTY.md"
[ ! -f "$root/src/mise/mise.remote.toml" ] || cp "$root/src/mise/mise.remote.toml" "$payload/mise/mise.remote.toml"
[ ! -f "$root/src/mise/mise.starship.toml" ] || cp "$root/src/mise/mise.starship.toml" "$payload/mise/mise.starship.toml"
cp -R "$root/src/scripts/." "$payload/scripts/"
cp -R "$root/src/dotfiles" "$payload/dotfiles"
[ -d "$nvim_source" ] || die "Neovim source is missing: $nvim_source"
command -v git >/dev/null 2>&1 || die 'Git is required to build the Neovim snapshot'
git -C "$nvim_source" archive --format=tar --output="$output/nvim-conf.tar" HEAD
tar -xf "$output/nvim-conf.tar" -C "$payload/vendor/nvim.conf"
rm "$output/nvim-conf.tar"
[ -d "$tmux_source" ] || die "Tmux source is missing: $tmux_source"
git -C "$tmux_source" archive --format=tar --output="$output/tmux-conf.tar" HEAD
tar -xf "$output/tmux-conf.tar" -C "$payload/vendor/tmux.conf"
rm "$output/tmux-conf.tar"
cp "$janet" "$payload/runtime/bin/$platform/janet"
cp "$mise" "$payload/runtime/bin/$platform/mise"
chmod 0755 "$output/bootstrap.sh" "$payload/bootstrap.sh" "$files/ds" \
	"$payload/runtime/bin/$platform/janet" "$payload/runtime/bin/$platform/mise"

tab=$(printf '\t')
printf 'ds-bundle-v1%s%s\n' "$tab" "$version" >"$output/manifest.tsv"
find "$files" -type f -print | LC_ALL=C sort | while IFS= read -r source; do
	path=${source#"$files/"}
	# push.sh interpolates this path into a remote shell command, so restrict
	# the character class at production rather than at every consumer.
	case "$path" in *[!0-9A-Za-z._/-]*) die "unsafe bundle path: $path" ;; esac
	mode=0644
	[ -x "$source" ] && mode=0755
	digest=$(sha256_file "$source")
	printf 'file%s%s%s%s%s%s\n' "$tab" "$mode" "$tab" "$digest" "$tab" "$path"
done >>"$output/manifest.tsv"

sha256_file "$output/manifest.tsv" >"$output/manifest.sha256"
printf '%s\n' "$output"
