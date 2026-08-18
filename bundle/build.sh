#!/bin/sh

set -eu

die() {
	printf '%s\n' "df bundle: $*" >&2
	exit 1
}

usage() {
	printf '%s\n' 'usage: bundle/build.sh --version VERSION --platform PLATFORM --janet FILE --mise FILE --output DIR'
}

root=$(dirname -- "$0")/..
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

if command -v sha256sum >/dev/null 2>&1; then
	checksum_kind=sha256sum
elif command -v shasum >/dev/null 2>&1; then
	checksum_kind=shasum
else
	die 'a SHA-256 utility is required'
fi

sha256_file() {
	case "$checksum_kind" in
	sha256sum) sha256sum "$1" | {
		read -r digest _rest
		printf '%s\n' "$digest"
	} ;;
	shasum) shasum -a 256 "$1" | {
		read -r digest _rest
		printf '%s\n' "$digest"
	} ;;
	esac
}

files=$output/files
nvim_source=${DF_NVIM_SOURCE:-$root/../nvim.conf}
tmux_source=${DF_TMUX_SOURCE:-$root/../tmux.conf}
DF_MISE=${DF_GENERATOR_MISE:-mise} "$root/scripts/generate.sh" --check >/dev/null
mkdir -p "$files/runtime/bin/$platform" "$files/scripts" "$files/vendor/nvim.conf" "$files/vendor/tmux.conf"
cp "$root/bootstrap.sh" "$output/bootstrap.sh"
cp "$root/bootstrap.sh" "$files/bootstrap.sh"
cp "$root/ds" "$files/ds"
cp "$root/mise.toml" "$files/mise.toml"
cp "$root/catalog.toml" "$files/catalog.toml"
[ ! -f "$root/mise.remote.toml" ] || cp "$root/mise.remote.toml" "$files/mise.remote.toml"
[ ! -f "$root/mise.starship.toml" ] || cp "$root/mise.starship.toml" "$files/mise.starship.toml"
cp -R "$root/scripts/." "$files/scripts/"
cp -R "$root/dotfiles" "$files/dotfiles"
[ -d "$nvim_source" ] || die "Neovim source is missing: $nvim_source"
command -v git >/dev/null 2>&1 || die 'Git is required to build the Neovim snapshot'
git -C "$nvim_source" archive --format=tar --output="$output/nvim-conf.tar" HEAD
tar -xf "$output/nvim-conf.tar" -C "$files/vendor/nvim.conf"
rm "$output/nvim-conf.tar"
[ -d "$tmux_source" ] || die "Tmux source is missing: $tmux_source"
git -C "$tmux_source" archive --format=tar --output="$output/tmux-conf.tar" HEAD
tar -xf "$output/tmux-conf.tar" -C "$files/vendor/tmux.conf"
rm "$output/tmux-conf.tar"
cp "$janet" "$files/runtime/bin/$platform/janet"
cp "$mise" "$files/runtime/bin/$platform/mise"
chmod 0755 "$output/bootstrap.sh" "$files/bootstrap.sh" "$files/ds" \
	"$files/runtime/bin/$platform/janet" "$files/runtime/bin/$platform/mise"

tab=$(printf '\t')
printf 'df-bundle-v1%s%s\n' "$tab" "$version" >"$output/manifest.tsv"
find "$files" -type f -print | LC_ALL=C sort | while IFS= read -r source; do
	path=${source#"$files/"}
	mode=0644
	[ -x "$source" ] && mode=0755
	digest=$(sha256_file "$source")
	printf 'file%s%s%s%s%s%s\n' "$tab" "$mode" "$tab" "$digest" "$tab" "$path"
done >>"$output/manifest.tsv"

sha256_file "$output/manifest.tsv" >"$output/manifest.sha256"
printf '%s\n' "$output"
