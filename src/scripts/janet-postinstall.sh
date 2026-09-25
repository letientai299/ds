#!/bin/sh
set -eu

[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || exit 0
: "${MISE_TOOL_INSTALL_PATH:?mise install path is required}"
binary=$MISE_TOOL_INSTALL_PATH/bin/janet
file "$binary" | grep -q 'Mach-O 64-bit executable arm64' && exit 0

# Upstream arm64 archive contains x86_64 Janet.
source_dir=$MISE_TOOL_INSTALL_PATH/src
header_dir=$MISE_TOOL_INSTALL_PATH/include
temporary=$(mktemp "$MISE_TOOL_INSTALL_PATH/bin/janet.part.XXXXXX")
trap 'rm -f "$temporary"' EXIT HUP INT TERM
clang -std=c99 -O2 -DNDEBUG -arch arm64 -mmacosx-version-min=12.0 \
	-I "$header_dir" "$source_dir/janet.c" "$source_dir/shell.c" -lm -o "$temporary"
strip -x "$temporary"
codesign --force --sign - --timestamp=none "$temporary"
chmod 0755 "$temporary"
mv "$temporary" "$binary"
trap - EXIT HUP INT TERM
"$binary" --version
