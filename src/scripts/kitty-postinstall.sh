#!/bin/sh
set -eu
: "${MISE_TOOL_INSTALL_PATH:?mise installation path is required}"
if [ "$(uname -s)" = Darwin ]; then
	image=$(find "$MISE_TOOL_INSTALL_PATH" -name '*.dmg' -print -quit)
	[ -n "$image" ] || {
		printf '%s\n' 'kitty: installation image missing' >&2
		exit 1
	}
	mount=$(mktemp -d)
	trap 'hdiutil detach "$mount" >/dev/null 2>&1 || true; rmdir "$mount" 2>/dev/null || true' EXIT
	hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$image"
	cp -R "$mount/kitty.app" "$MISE_TOOL_INSTALL_PATH/kitty.app"
	mkdir -p "$MISE_TOOL_INSTALL_PATH/bin"
	for command in kitty kitten; do
		ln -s "../kitty.app/Contents/MacOS/$command" "$MISE_TOOL_INSTALL_PATH/bin/$command"
	done
	hdiutil detach -quiet "$mount"
	rmdir "$mount"
	trap - EXIT
	rm "$image"
fi
"$MISE_TOOL_INSTALL_PATH/bin/kitty" --version
