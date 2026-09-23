#!/bin/sh
set -eu

# Upstream Linux binaries require glibc.
[ -f /etc/alpine-release ] || exit 0
: "${MISE_TOOL_INSTALL_PATH:?mise install path is required}"
: "${DS_NVIM_SOURCE_SHA256:?Neovim source checksum is required}"
version=${MISE_TOOL_INSTALL_PATH##*/}
case "$version" in '' | *[!0-9.]*)
	echo 'invalid Neovim version' >&2
	exit 1
	;;
esac
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-neovim.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM
curl -fL --retry 2 "https://github.com/neovim/neovim/archive/refs/tags/v$version.tar.gz" \
	--output "$work/source.tar.gz"
printf '%s  %s\n' "$DS_NVIM_SOURCE_SHA256" "$work/source.tar.gz" | sha256sum -c -
tar -xzf "$work/source.tar.gz" --strip-components=1 -C "$work"
cmake -S "$work/cmake.deps" -B "$work/.deps" -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build "$work/.deps" --parallel 2
cmake -S "$work" -B "$work/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
	"-DCMAKE_INSTALL_PREFIX=$MISE_TOOL_INSTALL_PATH" "-DCMAKE_PREFIX_PATH=$work/.deps/usr"
cmake --build "$work/build" --parallel 2
cmake --install "$work/build"
"$MISE_TOOL_INSTALL_PATH/bin/nvim" --headless --clean +qa
