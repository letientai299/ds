#!/bin/sh

set -eu

mode=${1:?layer test mode is required}
case "$mode" in core | remote | core-remote) ;; *) exit 2 ;; esac
root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
dist=${DS_RUNTIME_DIST:-$root/dist/runtime}
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-layer.XXXXXX")
# shellcheck source=tests/isolate.sh
. "$root/tests/isolate.sh"
isolate_home "$work/isolated-home"
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM

case "$(uname -m)" in
arm64 | aarch64) platforms=linux-arm64-musl ;;
x86_64 | amd64) platforms=linux-x64-musl ;;
*) exit 1 ;;
esac
case "${DS_CORE_CASES:-native}" in
native) ;;
all) platforms='linux-arm64-musl linux-x64-musl' ;;
*)
	printf '%s\n' 'DS_CORE_CASES must be native or all' >&2
	exit 1
	;;
esac

run_case() (
	platform=$1
	name=$2
	image=$3
	case "$platform" in
	linux-arm64-musl) docker_platform=linux/arm64 ;;
	linux-x64-musl) docker_platform=linux/amd64 ;;
	esac
	snapshot=$work/snapshot-$platform
	manifest_sha=$(sed -n '1p' "$snapshot/manifest.sha256")
	started=$(date +%s)
	if docker run --rm --platform "$docker_platform" \
		--volume "$snapshot:/snapshot:ro" \
		--volume "$root/tests/layer-check.sh:/checks.sh:ro" \
		--tmpfs /home/test:exec,mode=1777 \
		--env GITHUB_TOKEN \
		--env HOME=/home/test \
		--env XDG_CACHE_HOME=/home/test/.cache \
		--env XDG_CONFIG_HOME=/home/test/.config \
		--env XDG_DATA_HOME=/home/test/.local/share \
		--env XDG_STATE_HOME=/home/test/.local/state \
		--env MISE_CACHE_DIR=/home/test/.cache/mise \
		--env MISE_CONFIG_DIR=/home/test/.config/ds/mise \
		--env MISE_DATA_DIR=/home/test/.local/share/mise \
		--env MISE_STATE_DIR=/home/test/.local/state/mise \
		--env DEBIAN_FRONTEND=noninteractive \
		"$image" sh /checks.sh "$mode" "$manifest_sha" \
		>"$work/$platform-$name.log" 2>&1; then
		printf '%s %s: ok in %ss\n' "$name" "$mode" "$(($(date +%s) - started))"
		grep -E '^(core|remote): ok in ' "$work/$platform-$name.log"
	else
		cat "$work/$platform-$name.log" >&2
		printf '%s %s: failed\n' "$name" "$mode" >&2
		exit 1
	fi
)

failed=0
for platform in $platforms; do
	"$root/src/bundle/build.sh" --version 0.1.0-e2e --platform "$platform" \
		--janet "$dist/bin/$platform/janet" --mise "$dist/bin/$platform/mise" \
		--output "$work/snapshot-$platform" >/dev/null
	if [ "${DS_CHECK_JOBS:-2}" = 1 ]; then
		run_case "$platform" alpine "${DS_ALPINE_IMAGE:?run through mise}" || failed=1
		run_case "$platform" ubuntu "${DS_UBUNTU_IMAGE:?run through mise}" || failed=1
	else
		run_case "$platform" alpine "${DS_ALPINE_IMAGE:?run through mise}" &
		alpine_pid=$!
		run_case "$platform" ubuntu "${DS_UBUNTU_IMAGE:?run through mise}" &
		ubuntu_pid=$!
		wait "$alpine_pid" || failed=1
		wait "$ubuntu_pid" || failed=1
	fi
done
[ "$failed" -eq 0 ]
printf '%s: ok\n' "$mode"
