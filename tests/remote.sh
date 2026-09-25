#!/bin/sh

set -eu

fail() {
	printf '%s\n' "remote: $*" >&2
	exit 1
}

: "${DS_ALPINE_IMAGE:?run through mise so DS_ALPINE_IMAGE is set}"
: "${DS_UBUNTU_IMAGE:?run through mise so DS_UBUNTU_IMAGE is set}"

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
dist=${DS_RUNTIME_DIST:-$root/dist/runtime}
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-remote.XXXXXX")
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
"$root/src/bundle/build.sh" \
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
		--env MISE_CONFIG_DIR=/home/test/.config/ds/mise \
		--env MISE_DATA_DIR=/home/test/.local/share/mise \
		--env MISE_STATE_DIR=/home/test/.local/state/mise \
		--env DEBIAN_FRONTEND=noninteractive \
		"$image" /bin/sh -c '
            set -eu
            installed=$(/snapshot/bootstrap.sh \
                --source /snapshot \
                --prefix "$HOME/.local/share/ds" \
                --manifest-sha256 "$1")
            "$installed/ds" apply remote
            "$installed/ds" status remote --verbose >"$HOME/status"
            grep -q "^  missing docker$" "$HOME/status"
            grep -q "^  installed tmux$" "$HOME/status"
            grep -q "^  installed zoxide " "$HOME/status"
            grep -q "^  installed yazi " "$HOME/status"
            command -v file >/dev/null
            # The first source primes the git-version cache; repeated sourcing must be stable.
            zsh -f -c "source \"$HOME/.config/ds/shell.zsh\""
            find "$HOME" -print | sort > /tmp/ds-before-paths
            find "$HOME" -type f -exec sha256sum {} \; | sort > /tmp/ds-before-hashes
            zsh -f -c "
                set -e
                source \"$HOME/.config/ds/shell.zsh\"
                (( \$+functions[yazi_cd] ))
                [[ \$YAZI_CONFIG_HOME == \$XDG_CONFIG_HOME/ds/yazi ]]
                [[ \$aliases[r] == yazi_cd ]]
            "
            find "$HOME" -print | sort > /tmp/ds-after-paths
            find "$HOME" -type f -exec sha256sum {} \; | sort > /tmp/ds-after-hashes
            cmp -s /tmp/ds-before-paths /tmp/ds-after-paths
            cmp -s /tmp/ds-before-hashes /tmp/ds-after-hashes

            zsh -f -c "
                set -e
                source \"$HOME/.config/ds/shell.zsh\"
                zoxide --version >/dev/null
                tm new-session -d -s ds-e2e sleep 30
                [[ \"\$(tm show-options -sv set-clipboard)\" = on ]]
                tm show-options -sv terminal-features | grep -q clipboard
                tm has-session -t ds-e2e
                tm kill-server
            "
            printf "%s\n" remote-ready
        ' ds-remote "$manifest_sha" >"$out"; then
		cat "$out" >&2
		fail "$name container checks failed"
	fi
	grep -q '^remote-ready$' "$out" || fail "$name did not complete remote checks"
}

run_case "$DS_ALPINE_IMAGE" alpine
run_case "$DS_UBUNTU_IMAGE" ubuntu

printf '%s\n' 'remote: ok'
