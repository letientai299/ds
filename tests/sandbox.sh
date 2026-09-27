#!/bin/sh

# Runs a command against a copy of this checkout inside a throwaway container,
# so tests never see the real home, mise directories, or checkout. The checkout
# and the sibling Neovim, Tmux, and Kitty repositories are mounted read-only.
#
# --docker also mounts the host Docker socket for tests that start containers.
# The engine resolves bind-mount sources on the host, so the copy and TMPDIR
# then live in a host temporary directory mounted at the same absolute path.

set -eu

die() {
	printf '%s\n' "ds sandbox: $*" >&2
	exit 1
}

if [ "${DS_TEST_SANDBOX:-}" = 1 ]; then
	copy=${DS_SANDBOX_COPY:-/tmp/ds}
	mkdir -p "$copy" "$HOME" "${TMPDIR:-/tmp}"
	# .git is excluded because worktrees point it outside the mount. The
	# verified runtime downloads are seeded to skip refetching them.
	tar -C /mnt/ds --exclude=./.git --exclude=./.ai \
		--exclude=./dist/runtime/bin --exclude='./dist/runtime/.build-*' -cf - . |
		tar -C "$copy" -xf -
	cd "$copy"
	exec mise exec -- "$@"
fi

docker_mode=false
[ "${1:-}" != --docker ] || {
	docker_mode=true
	shift
}
[ "$#" -gt 0 ] || die 'usage: tests/sandbox.sh [--docker] COMMAND [ARG...]'
: "${DS_UBUNTU_IMAGE:?run through mise so DS_UBUNTU_IMAGE is set}"
command -v docker >/dev/null 2>&1 || die 'Docker is required'
root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
image=ds-test:local

printf '%s\n' 'ds sandbox: building test image' >&2
docker buildx build --load --quiet \
	--file "$root/tests/Dockerfile" \
	--tag "$image" \
	--build-arg DS_UBUNTU_IMAGE \
	--build-arg DS_JANET_VERSION \
	--build-arg DS_JANET_SOURCE_SHA256 \
	--build-arg DS_JANET_HEADER_SHA256 \
	--build-arg DS_JANET_SHELL_SHA256 \
	"$root" >/dev/null

# Docker flags are appended after the command, which then rotates to the end.
count=$#
set -- "$@" --volume "$root:/mnt/ds:ro"
for name in nvim tmux kitty; do
	case "$name" in
	nvim) source=${DS_NVIM_SOURCE:-$root/../nvim.conf} ;;
	tmux) source=${DS_TMUX_SOURCE:-$root/../tmux.conf} ;;
	kitty) source=${DS_KITTY_SOURCE:-$root/../kitty.conf} ;;
	esac
	[ -d "$source" ] || continue
	source=$(CDPATH='' cd "$source" && pwd)
	upper=$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')
	set -- "$@" --volume "$source:/mnt/$name.conf:ro" --env "DS_${upper}_SOURCE=/mnt/$name.conf"
done

shared=
if [ "$docker_mode" = true ]; then
	socket=/var/run/docker.sock
	socket_group=$(docker run --rm --volume "$socket:$socket" --entrypoint stat "$image" -c %g "$socket")
	shared=$(mktemp -d "${TMPDIR:-/tmp}/ds-sandbox.XXXXXX")
	shared=$(CDPATH='' cd -P "$shared" && pwd)
	# Nested root containers leave root-owned files, so root removes them.
	trap 'docker run --rm --user 0 --volume "$shared:$shared" --entrypoint rm "$image" \
		-rf "$shared/ds" "$shared/tmp" >/dev/null 2>&1; rmdir "$shared"' EXIT
	trap 'exit 143' HUP INT TERM
	set -- "$@" --volume "$socket:$socket" --group-add "$socket_group" \
		--volume "$shared:$shared" \
		--env "DS_SANDBOX_COPY=$shared/ds" --env "TMPDIR=$shared/tmp"
fi

[ ! -t 0 ] || [ ! -t 1 ] || set -- "$@" --tty
set -- "$@" "$image" /mnt/ds/tests/sandbox.sh
while [ "$count" -gt 0 ]; do
	set -- "$@" "$1"
	shift
	count=$((count - 1))
done

# The network stays on: the snapshot build fetches Kitty's Go modules.
# GITHUB_TOKEN, forwarded by name, lifts mise's GitHub API rate limit.
status=0
docker run --rm --init \
	--read-only \
	--tmpfs /tmp:exec,mode=1777 \
	--cap-drop ALL \
	--security-opt no-new-privileges \
	--user "$(id -u):$(id -g)" \
	--env HOME=/tmp/home \
	--env DS_TEST_GO_CACHE=/tmp/go \
	--env "DS_CHECK_JOBS=${DS_CHECK_JOBS:-}" \
	--env GITHUB_TOKEN \
	--workdir /tmp \
	"$@" || status=$?
exit "$status"
