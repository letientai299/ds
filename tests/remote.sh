#!/bin/sh

set -eu

fail() {
	printf '%s\n' "remote: $*" >&2
	exit 1
}

: "${DF_ALPINE_IMAGE:?run through mise so DF_ALPINE_IMAGE is set}"
: "${DF_UBUNTU_IMAGE:?run through mise so DF_UBUNTU_IMAGE is set}"

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
dist=${DF_RUNTIME_DIST:-$root/dist/runtime}
work=$(mktemp -d "${TMPDIR:-/tmp}/df-remote.XXXXXX")
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
"$root/bundle/build.sh" \
	--version 0.1.0-remote \
	--platform "$platform" \
	--janet "$dist/bin/$platform/janet" \
	--mise "$dist/bin/$platform/mise" \
	--output "$snapshot" >/dev/null
manifest_sha=$(sed -n '1p' "$snapshot/manifest.sha256")

run_case() {
	image=$1
	name=$2
	home=$work/home-$name
	out=$work/$name.out
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
		--env MISE_CONFIG_DIR=/home/test/.config/df/mise \
		--env MISE_DATA_DIR=/home/test/.local/share/mise \
		--env MISE_STATE_DIR=/home/test/.local/state/mise \
		--env DEBIAN_FRONTEND=noninteractive \
		"$image" /bin/sh -c '
            set -eu
            installed=$(/snapshot/bootstrap.sh \
                --source /snapshot \
                --prefix "$HOME/.local/share/df" \
                --manifest-sha256 "$1")
            "$installed/ds" apply remote
            "$installed/ds" status remote >"$HOME/status"
            grep -q "^  missing docker$" "$HOME/status"
            grep -q "^  present tmux$" "$HOME/status"
            grep -q "^  present zoxide$" "$HOME/status"
            grep -q "^  present bat$" "$HOME/status"
            grep -q "^  present delta$" "$HOME/status"

            find "$HOME" -print | sort > /tmp/df-before-paths
            find "$HOME" -type f -exec sha256sum {} \; | sort > /tmp/df-before-hashes
            zsh -f -c "
                set -e
                source \"$HOME/.config/df/shell.zsh\"
                (( \$+functions[z] ))
            "
            find "$HOME" -print | sort > /tmp/df-after-paths
            find "$HOME" -type f -exec sha256sum {} \; | sort > /tmp/df-after-hashes
            cmp -s /tmp/df-before-paths /tmp/df-after-paths
            cmp -s /tmp/df-before-hashes /tmp/df-after-hashes

            zsh -f -c "
                set -e
                source \"$HOME/.config/df/shell.zsh\"
                zoxide --version >/dev/null
                bat --version >/dev/null
                delta --version >/dev/null
                tm new-session -d -s df-e2e sleep 30
                [[ \"\$(tm show-options -sv set-clipboard)\" = on ]]
                tm show-options -sv terminal-features | grep -q clipboard
                tm has-session -t df-e2e
                tm kill-server
            "
            printf "%s\n" remote-ready
        ' df-remote "$manifest_sha" >"$out"; then
		cat "$out" >&2
		fail "$name container checks failed"
	fi
	grep -q '^remote-ready$' "$out" || fail "$name did not complete remote checks"
}

run_case "$DF_ALPINE_IMAGE" alpine
run_case "$DF_UBUNTU_IMAGE" ubuntu

printf '%s\n' 'remote: ok'
