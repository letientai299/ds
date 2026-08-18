#!/bin/sh

set -eu

fail() {
	printf '%s\n' "rocky: $*" >&2
	exit 1
}

: "${DS_ROCKY_IMAGE:?run through mise so DS_ROCKY_IMAGE is set}"

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
dist=${DS_RUNTIME_DIST:-$root/dist/runtime}
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-rocky.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

case "$(uname -m)" in
arm64 | aarch64)
	platform=linux-arm64-musl
	docker_platform=linux/arm64
	;;
x86_64 | amd64)
	platform=linux-x64-musl
	docker_platform=linux/amd64
	;;
*) fail 'unsupported native architecture' ;;
esac

snapshot=$work/snapshot
home=$work/home
"$root/src/bundle/build.sh" \
	--version 0.1.0-rocky \
	--platform "$platform" \
	--janet "$dist/bin/$platform/janet" \
	--mise "$dist/bin/$platform/mise" \
	--output "$snapshot" >/dev/null
manifest_sha=$(sed -n '1p' "$snapshot/manifest.sha256")
mkdir -p "$home"

docker run --rm \
	--platform "$docker_platform" \
	--volume "$snapshot:/snapshot:ro" \
	--volume "$home:/home/test:rw" \
	--env HOME=/home/test \
	--env XDG_CACHE_HOME=/home/test/.cache \
	--env XDG_CONFIG_HOME=/home/test/.config \
	--env XDG_DATA_HOME=/home/test/.local/share \
	--env XDG_STATE_HOME=/home/test/.local/state \
	--env MISE_CACHE_DIR=/home/test/.cache/mise \
	--env MISE_CONFIG_DIR=/home/test/.config/ds/mise \
	--env MISE_DATA_DIR=/home/test/.local/share/mise \
	--env MISE_STATE_DIR=/home/test/.local/state/mise \
	"$DS_ROCKY_IMAGE" /bin/sh -c '
        set -eu
        installed=$(/snapshot/bootstrap.sh \
            --source /snapshot \
            --prefix "$HOME/.local/share/ds" \
            --manifest-sha256 "$1")
        "$installed/ds" apply core
        "$installed/ds" status core >"$HOME/status-first"
        "$installed/ds" apply core
        "$installed/ds" status core >"$HOME/status-second"
        grep -q "^core: complete$" "$HOME/status-first"
        grep -q "^core: complete$" "$HOME/status-second"
        zsh -f -c "
            set -e
            source \"$HOME/.config/ds/shell.zsh\"
            command -v mise fd fzf rg nvim nnn jq xh ds >/dev/null
            nvim --version >/dev/null
            nnn -V >/dev/null
        "
    ' ds-rocky "$manifest_sha"

printf '%s\n' 'rocky: ok'
