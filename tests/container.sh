#!/bin/sh

set -eu

fail() {
	printf '%s\n' "container: $*" >&2
	exit 1
}

: "${DS_ALPINE_IMAGE:?run through mise so DS_ALPINE_IMAGE is set}"
: "${DS_UBUNTU_IMAGE:?run through mise so DS_UBUNTU_IMAGE is set}"

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
dist=${DS_RUNTIME_DIST:-$root/dist/runtime}
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-container.XXXXXX")
# shellcheck source=tests/isolate.sh
. "$(dirname -- "$0")/isolate.sh"
isolate_home "$work/isolated-home"
trap 'rm -rf "$work"' EXIT HUP INT TERM

run_case() {
	platform=$1
	docker_platform=$2
	image=$3
	name=$4
	snapshot=$work/snapshot-$platform

	if [ ! -d "$snapshot" ]; then
		"$root/src/bundle/build.sh" \
			--version 0.0.0-container \
			--platform "$platform" \
			--janet "$dist/bin/$platform/janet" \
			--mise "$dist/bin/$platform/mise" \
			--output "$snapshot" >/dev/null
	fi
	manifest_sha=$(sed -n '1p' "$snapshot/manifest.sha256")

	docker run --rm \
		--platform "$docker_platform" \
		--network none \
		--read-only \
		--user 1000:1000 \
		--cap-drop ALL \
		--security-opt no-new-privileges \
		--tmpfs /tmp:rw,nosuid,nodev,noexec \
		--volume "$snapshot:/snapshot:ro" \
		--tmpfs /home/test:exec,mode=1777 \
		--env HOME=/home/test \
		--env XDG_CACHE_HOME=/home/test/.cache \
		--env XDG_CONFIG_HOME=/home/test/.config \
		--env XDG_DATA_HOME=/home/test/.local/share \
		--env XDG_STATE_HOME=/home/test/.local/state \
		--env MISE_CACHE_DIR=/home/test/.cache/mise \
		--env MISE_CONFIG_DIR=/home/test/.config/ds/mise \
		--env MISE_DATA_DIR=/home/test/.local/share/mise \
		--env MISE_STATE_DIR=/home/test/.local/state/mise \
		--env ZDOTDIR=/home/test/.config/zsh \
		"$image" /bin/sh -c '
            set -eu
            test ! -e "$HOME/.zshrc"
            installed=$(/snapshot/bootstrap.sh \
                --source /snapshot \
                --prefix "$HOME/.local/share/ds" \
                --manifest-sha256 "$1")
            "$installed/src/runtime/bin/$2/mise" --version
            "$installed/ds" status core
            test ! -e "$HOME/.zshrc"
            test ! -e "$HOME/.config/zsh/.zshrc"
        ' ds-container "$manifest_sha" "$platform" >"$work/$platform-$name.out"

	grep -q '^core: incomplete$' "$work/$platform-$name.out" || fail "$name $platform did not resolve core"
}

run_architecture() (
	run_case "$1" "$2" "$DS_ALPINE_IMAGE" alpine
	run_case "$1" "$2" "$DS_UBUNTU_IMAGE" ubuntu
)

if [ "${DS_CHECK_JOBS:-2}" = 1 ]; then
	run_architecture linux-arm64-musl linux/arm64
	run_architecture linux-x64-musl linux/amd64
else
	run_architecture linux-arm64-musl linux/arm64 >"$work/arm64.log" 2>&1 &
	arm64_pid=$!
	run_architecture linux-x64-musl linux/amd64 >"$work/x64.log" 2>&1 &
	x64_pid=$!
	failed=0
	wait "$arm64_pid" || failed=1
	wait "$x64_pid" || failed=1
	cat "$work/arm64.log" "$work/x64.log"
	[ "$failed" -eq 0 ] || fail 'delivery matrix failed'
fi

printf '%s\n' 'containers: ok'
