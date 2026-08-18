#!/bin/sh

set -eu

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
dist=${DF_RUNTIME_DIST:-$root/dist/runtime}
work=$(mktemp -d "${TMPDIR:-/tmp}/df-performance.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

case "$(uname -s):$(uname -m)" in
Darwin:arm64) platform=macos-arm64 ;;
Darwin:x86_64) platform=macos-x64 ;;
Linux:aarch64 | Linux:arm64) platform=linux-arm64-musl ;;
Linux:x86_64 | Linux:amd64) platform=linux-x64-musl ;;
*)
	printf '%s\n' 'performance: unsupported platform' >&2
	exit 1
	;;
esac

snapshot=$work/snapshot
archive=$work/df-performance.tar.gz
home=$work/home
mkdir -p "$home"

"$root/bundle/build.sh" \
	--version performance \
	--platform "$platform" \
	--janet "$dist/bin/$platform/janet" \
	--mise "$dist/bin/$platform/mise" \
	--output "$snapshot" >/dev/null
"$root/bundle/pack.sh" --snapshot "$snapshot" --output "$archive" >/dev/null

runtime_bytes=$(wc -c <"$dist/bin/$platform/janet" | tr -d ' ')
mise_bytes=$(wc -c <"$dist/bin/$platform/mise" | tr -d ' ')
bundle_bytes=$(wc -c <"$archive" | tr -d ' ')
installed_bytes=$(find "$snapshot/files" -type f -exec wc -c {} \; | awk '{total += $1} END {printf "%.0f", total}')

for runtime_platform in macos-arm64 macos-x64 linux-arm64-musl linux-x64-musl; do
	runtime=$dist/bin/$runtime_platform/janet
	[ -x "$runtime" ] || {
		printf '%s\n' "performance: missing Janet runtime: $runtime_platform" >&2
		exit 1
	}
	gzip -cn "$runtime" >"$work/janet-$runtime_platform.gz"
done

measure() {
	name=$1
	command=$2
	DF_BENCH_COMMAND=$command zsh -fc '
        zmodload zsh/datetime
        typeset -F start elapsed average
        start=$EPOCHREALTIME
        repeat 25 { eval "$DF_BENCH_COMMAND" }
        elapsed=$(( (EPOCHREALTIME - start) * 1000.0 ))
        average=$(( elapsed / 25.0 ))
        printf "%s_ms\t%.3f\n" "$1" "$average"
    ' df-performance "$name"
}

measure_once() {
	name=$1
	command=$2
	DF_BENCH_COMMAND=$command zsh -fc '
        zmodload zsh/datetime
        typeset -F start elapsed
        start=$EPOCHREALTIME
        eval "$DF_BENCH_COMMAND"
        elapsed=$(( (EPOCHREALTIME - start) * 1000.0 ))
        printf "%s_ms\t%.3f\n" "$1" "$elapsed"
    ' df-performance "$name"
}

printf '%s\t%s\n' platform "$platform"
printf '%s\t%s\n' janet_runtime_bytes "$runtime_bytes"
printf '%s\t%s\n' mise_runtime_bytes "$mise_bytes"
printf '%s\t%s\n' installed_snapshot_bytes "$installed_bytes"
printf '%s\t%s\n' compressed_bundle_bytes "$bundle_bytes"
for runtime_platform in macos-arm64 macos-x64 linux-arm64-musl linux-x64-musl; do
	key=$(printf '%s' "$runtime_platform" | tr - _)
	printf 'janet_%s_installed_bytes\t%s\n' "$key" "$(wc -c <"$dist/bin/$runtime_platform/janet" | tr -d ' ')"
	printf 'janet_%s_compressed_bytes\t%s\n' "$key" "$(wc -c <"$work/janet-$runtime_platform.gz" | tr -d ' ')"
done

common="HOME='$home' XDG_CONFIG_HOME='$home/.config' XDG_DATA_HOME='$home/.local/share' XDG_STATE_HOME='$home/.local/state'"
manifest_sha=$(sed -n '1p' "$snapshot/manifest.sha256")
measure janet_startup "'$dist/bin/$platform/janet' -e '(print :ok)' >/dev/null"
measure stage0_verify "'$snapshot/bootstrap.sh' --source '$snapshot' --manifest-sha256 '$manifest_sha' --verify-only >/dev/null"
measure status_dispatch "$common '$snapshot/files/ds' status core >/dev/null"
measure shell_init_dispatch "$common '$snapshot/files/ds' shell-init >/dev/null"
measure portable_shell_source "$common PATH=/usr/bin:/bin zsh -dfc 'source $snapshot/files/dotfiles/shell.zsh'"

remote_home=$work/remote-home
fake_ssh=$work/fake-ssh
mkdir -p "$remote_home"
# shellcheck disable=SC2016 # Variables belong to the generated fake SSH script.
printf '%s\n' \
	'#!/bin/sh' \
	'shift' \
	'HOME=$DF_BENCH_REMOTE_HOME exec /bin/sh -c "$1"' >"$fake_ssh"
chmod 0755 "$fake_ssh"
measure_once stage0_loopback_push "DF_BENCH_REMOTE_HOME='$remote_home' DF_SSH='$fake_ssh' '$root/bundle/push.sh' --snapshot '$snapshot' --host benchmark >/dev/null"
measure stage0_idempotent_push "$common DF_BENCH_REMOTE_HOME='$remote_home' DF_SSH='$fake_ssh' '$root/bundle/push.sh' --snapshot '$snapshot' --host benchmark >/dev/null"
