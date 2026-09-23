#!/bin/sh

set -eu

fail() {
	printf '%s\n' "performance-linux: $*" >&2
	exit 1
}

: "${DS_UBUNTU_IMAGE:?run through mise so DS_UBUNTU_IMAGE is set}"

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
dist=${DS_RUNTIME_DIST:-$root/dist/runtime}
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-performance-linux.XXXXXX")
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
mkdir -p "$home"
"$root/src/bundle/build.sh" \
	--version performance-linux \
	--platform "$platform" \
	--janet "$dist/bin/$platform/janet" \
	--mise "$dist/bin/$platform/mise" \
	--output "$snapshot" >/dev/null
manifest_sha=$(sed -n '1p' "$snapshot/manifest.sha256")

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
	--env DEBIAN_FRONTEND=noninteractive \
	"$DS_UBUNTU_IMAGE" /bin/sh -c '
        set -eu
        installed=$(/snapshot/bootstrap.sh \
            --source /snapshot \
            --prefix "$HOME/.local/share/ds" \
            --manifest-sha256 "$1")

		timed_apply() {
            label=$1
            shift
            start=$(date +%s%N)
            if ! "$installed/ds" "$@" >"/tmp/$label.log" 2>&1; then
                cat "/tmp/$label.log" >&2
                exit 1
            fi
            finish=$(date +%s%N)
            printf "%s_ms\t%s\n" "$label" "$(( (finish - start) / 1000000 ))"
		}

		network_received() {
			total=0
			for counter in /sys/class/net/*/statistics/rx_bytes; do
				value=$(cat "$counter")
				total=$((total + value))
			done
			printf "%s\n" "$total"
		}

		before=$(network_received)
		timed_apply core_cold apply core
		after=$(network_received)
		printf "core_downloaded_bytes\t%s\n" "$((after - before))"
		printf "core_mise_cache_kib\t%s\n" "$(du -sk "$MISE_CACHE_DIR" | cut -f1)"
		before=$after
		timed_apply core_noop apply core
		after=$(network_received)
		printf "core_noop_downloaded_bytes\t%s\n" "$((after - before))"
		before=$after
		timed_apply remote_incremental apply remote --skip docker
		after=$(network_received)
		printf "remote_downloaded_bytes\t%s\n" "$((after - before))"
		printf "remote_mise_cache_kib\t%s\n" "$(du -sk "$MISE_CACHE_DIR" | cut -f1)"
		before=$after
		timed_apply remote_noop apply remote --skip docker
		after=$(network_received)
		printf "remote_noop_downloaded_bytes\t%s\n" "$((after - before))"
        printf "home_total_kib\t%s\n" "$(du -sk "$HOME" | cut -f1)"

        find "$MISE_DATA_DIR/installs" -mindepth 1 -maxdepth 1 -type d -print |
            sort |
            while IFS= read -r directory; do
                name=${directory##*/}
				printf "mise_component_%s_kib\t%s\n" "$name" "$(du -skL "$directory" | cut -f1)"
            done

		for package in ca-certificates curl git nnn tmux zsh; do
			size=$(dpkg-query -W -f="\${Installed-Size}" "$package")
            printf "native_package_%s_kib\t%s\n" "$package" "$size"
        done
    ' ds-performance-linux "$manifest_sha"

printf '%s\n' 'performance-linux: ok'
