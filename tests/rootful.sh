#!/bin/sh

set -eu

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-rootful.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
log=$work/calls

printf '%s\n' '#!/bin/sh' 'exec "$@"' >"$work/sudo"
chmod 0755 "$work/sudo"
for name in apt-get systemctl usermod; do
	# shellcheck disable=SC2016
	printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$(basename "$0") $*" >>"$DS_ROOTFUL_LOG"' >"$work/$name"
	chmod 0755 "$work/$name"
done

if env DS_TARGET_USER=test "$root/src/scripts/docker-rootful.sh" >"$work/refused.out" 2>&1; then
	printf '%s\n' 'rootful: missing approvals were accepted' >&2
	exit 1
fi

DS_ROOTFUL_LOG=$log \
	DS_TARGET_USER=test \
	DS_SUDO=$work/sudo \
	DS_APT_GET=$work/apt-get \
	DS_SYSTEMCTL=$work/systemctl \
	DS_USERMOD=$work/usermod \
	"$root/src/scripts/docker-rootful.sh" \
	--approve-rootful --grant-docker-group >"$work/out"

grep -q '^apt-get update$' "$log"
grep -q '^apt-get install -y docker.io docker-buildx docker-compose-v2$' "$log"
grep -q '^systemctl enable --now docker.service$' "$log"
grep -q '^usermod -aG docker test$' "$log"
grep -q 'root-equivalent' "$work/out"

printf '%s\n' 'rootful: ok'
