#!/bin/sh

set -eu

fail() {
	printf '%s\n' "core: $*" >&2
	exit 1
}

: "${DS_ALPINE_IMAGE:?run through mise so DS_ALPINE_IMAGE is set}"
: "${DS_UBUNTU_IMAGE:?run through mise so DS_UBUNTU_IMAGE is set}"

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
dist=${DS_RUNTIME_DIST:-$root/dist/runtime}
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-core.XXXXXX")
host_uid=$(id -u)
host_gid=$(id -g)
trap 'rm -rf "$work"' EXIT HUP INT TERM

run_case() {
	platform=$1
	docker_platform=$2
	image=$3
	name=$4
	snapshot=$work/snapshot-$platform
	home=$work/home-$platform-$name

	if [ ! -d "$snapshot" ]; then
		"$root/src/bundle/build.sh" \
			--version 0.1.0-core \
			--platform "$platform" \
			--janet "$dist/bin/$platform/janet" \
			--mise "$dist/bin/$platform/mise" \
			--output "$snapshot" >/dev/null
	fi
	manifest_sha=$(sed -n '1p' "$snapshot/manifest.sha256")
	mkdir -p "$home"

	if ! docker run --rm \
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
		--env DEBIAN_FRONTEND=noninteractive \
		--env HOST_UID="$host_uid" \
		--env HOST_GID="$host_gid" \
		"$image" /bin/sh -c '
            set -eu
            installed=$(/snapshot/bootstrap.sh \
                --source /snapshot \
                --prefix "$HOME/.local/share/ds" \
                --manifest-sha256 "$1")
            "$installed/ds" apply core
            "$installed/ds" status core
            "$installed/ds" apply core
            "$installed/ds" status core
			find "$HOME" -print | sort > /tmp/ds-before-paths
			find "$HOME" -type f -exec sha256sum {} \; | sort > /tmp/ds-before-hashes
		zsh -f -c "
				set -e
				source \"$HOME/.config/ds/shell.zsh\"
				echo shell-sourced
                command -v mise fd fzf rg tree-sitter nvim zoxide jq xh ds >/dev/null
				echo commands-present
                [ -f \"$HOME/.config/nvim/init.lua\" ]
				echo nvim-config-present
            "
			find "$HOME" -print | sort > /tmp/ds-after-paths
			find "$HOME" -type f -exec sha256sum {} \; | sort > /tmp/ds-after-hashes
			if ! cmp -s /tmp/ds-before-paths /tmp/ds-after-paths; then
				printf "%s\n" "paths added during shell startup"
				comm -13 /tmp/ds-before-paths /tmp/ds-after-paths
				printf "%s\n" "paths removed during shell startup"
				comm -23 /tmp/ds-before-paths /tmp/ds-after-paths
				exit 1
			fi
			if ! cmp -s /tmp/ds-before-hashes /tmp/ds-after-hashes; then
				printf "%s\n" "file hashes changed during shell startup"
				diff -u /tmp/ds-before-hashes /tmp/ds-after-hashes || true
				exit 1
			fi
			zsh -f -c "
				set -e
				source \"$HOME/.config/ds/shell.zsh\"
                zoxide --version >/dev/null
                fd --version >/dev/null
                fzf --version >/dev/null
                rg --version >/dev/null
                tree-sitter --version >/dev/null
                jq --version >/dev/null
                xh --version >/dev/null
                nvim --version >/dev/null
                nvim --headless --clean +qa
				echo tools-executed
			"
            printf "%s\n" shell-ready
            chown -R "$HOST_UID:$HOST_GID" "$HOME"
		' ds-core "$manifest_sha" "$name" >"$work/$platform-$name.out"; then
		cat "$work/$platform-$name.out" >&2
		fail "$name $platform container checks failed"
	fi

	if [ "$(grep -c '^applied core$' "$work/$platform-$name.out")" -ne 2 ] ||
		[ "$(grep -c '^core: complete$' "$work/$platform-$name.out")" -ne 2 ] ||
		[ "$(grep -c '^shell-ready$' "$work/$platform-$name.out")" -ne 1 ]; then
		cat "$work/$platform-$name.out" >&2
		fail "$name $platform did not converge idempotently"
	fi
	if [ "$name" = alpine ] &&
		[ "$(grep -c '^optional-refresh-ready$' "$work/$platform-$name.out")" -ne 1 ]; then
		cat "$work/$platform-$name.out" >&2
		fail "$name $platform did not refresh the optional component"
	fi
}

case "${DS_CORE_CASES:-native}" in
native)
	case "$(uname -m)" in
	arm64 | aarch64)
		run_case linux-arm64-musl linux/arm64 "$DS_ALPINE_IMAGE" alpine
		run_case linux-arm64-musl linux/arm64 "$DS_UBUNTU_IMAGE" ubuntu
		;;
	x86_64 | amd64)
		run_case linux-x64-musl linux/amd64 "$DS_ALPINE_IMAGE" alpine
		run_case linux-x64-musl linux/amd64 "$DS_UBUNTU_IMAGE" ubuntu
		;;
	*) fail 'unsupported native architecture' ;;
	esac
	;;
all)
	run_case linux-arm64-musl linux/arm64 "$DS_ALPINE_IMAGE" alpine
	run_case linux-arm64-musl linux/arm64 "$DS_UBUNTU_IMAGE" ubuntu
	run_case linux-x64-musl linux/amd64 "$DS_ALPINE_IMAGE" alpine
	run_case linux-x64-musl linux/amd64 "$DS_UBUNTU_IMAGE" ubuntu
	;;
*) fail 'DS_CORE_CASES must be native or all' ;;
esac

printf '%s\n' 'core: ok'
