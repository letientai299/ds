#!/bin/sh

set -eu

fail() {
	printf '%s\n' "container: $*" >&2
	exit 1
}

: "${DF_ALPINE_IMAGE:?run through mise so DF_ALPINE_IMAGE is set}"
: "${DF_UBUNTU_IMAGE:?run through mise so DF_UBUNTU_IMAGE is set}"

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
dist=${DF_RUNTIME_DIST:-$root/dist/runtime}
work=$(mktemp -d "${TMPDIR:-/tmp}/df-container.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

run_case() {
	platform=$1
	docker_platform=$2
	image=$3
	name=$4
	snapshot=$work/snapshot-$platform
	home=$work/home-$platform-$name

	if [ ! -d "$snapshot" ]; then
		"$root/bundle/build.sh" \
			--version 0.0.0-container \
			--platform "$platform" \
			--janet "$dist/bin/$platform/janet" \
			--mise "$dist/bin/$platform/mise" \
			--output "$snapshot" >/dev/null
	fi
	manifest_sha=$(sed -n '1p' "$snapshot/manifest.sha256")
	mkdir -p "$home"
	chmod 0777 "$home"

	docker run --rm \
		--platform "$docker_platform" \
		--network none \
		--read-only \
		--user 1000:1000 \
		--cap-drop ALL \
		--security-opt no-new-privileges \
		--tmpfs /tmp:rw,nosuid,nodev,noexec \
		--volume "$snapshot:/snapshot:ro" \
		--volume "$home:/home/test:rw" \
		--env HOME=/home/test \
		--env XDG_CACHE_HOME=/home/test/.cache \
		--env XDG_CONFIG_HOME=/home/test/.config \
		--env XDG_DATA_HOME=/home/test/.local/share \
		--env XDG_STATE_HOME=/home/test/.local/state \
		--env MISE_CACHE_DIR=/home/test/.cache/mise \
		--env MISE_CONFIG_DIR=/home/test/.config/mise \
		--env MISE_DATA_DIR=/home/test/.local/share/mise \
		--env MISE_STATE_DIR=/home/test/.local/state/mise \
		--env ZDOTDIR=/home/test/.config/zsh \
		"$image" /bin/sh -c '
            set -eu
            test ! -e "$HOME/.zshrc"
            installed=$(/snapshot/bootstrap.sh \
                --source /snapshot \
                --prefix "$HOME/.local/share/df" \
                --manifest-sha256 "$1")
            "$installed/runtime/bin/$2/mise" --version
            "$installed/ds" status core
            test ! -e "$HOME/.zshrc"
            test ! -e "$HOME/.config/zsh/.zshrc"
        ' df-container "$manifest_sha" "$platform" >"$work/$platform-$name.out"

	grep -q '^core: incomplete$' "$work/$platform-$name.out" || fail "$name $platform did not resolve core"
	[ ! -e "$home/.zshrc" ] || fail "$name $platform touched .zshrc"
	[ ! -e "$home/.config/zsh/.zshrc" ] || fail "$name $platform touched ZDOTDIR"
}

run_case linux-arm64-musl linux/arm64 "$DF_ALPINE_IMAGE" alpine
run_case linux-arm64-musl linux/arm64 "$DF_UBUNTU_IMAGE" ubuntu
run_case linux-x64-musl linux/amd64 "$DF_ALPINE_IMAGE" alpine
run_case linux-x64-musl linux/amd64 "$DF_UBUNTU_IMAGE" ubuntu

printf '%s\n' 'containers: ok'
