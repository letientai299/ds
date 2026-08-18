#!/bin/sh

set -eu

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/df-rootful.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
log=$work/calls

printf '%s\n' '#!/bin/sh' 'exec "$@"' >"$work/sudo"
chmod 0755 "$work/sudo"
for name in apt-get systemctl usermod; do
	# shellcheck disable=SC2016
	printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$(basename "$0") $*" >>"$DF_ROOTFUL_LOG"' >"$work/$name"
	chmod 0755 "$work/$name"
done

if env DF_TARGET_USER=test "$root/scripts/docker-rootful.sh" >"$work/refused.out" 2>&1; then
	printf '%s\n' 'rootful: missing approvals were accepted' >&2
	exit 1
fi

DF_ROOTFUL_LOG=$log \
	DF_TARGET_USER=test \
	DF_SUDO=$work/sudo \
	DF_APT_GET=$work/apt-get \
	DF_SYSTEMCTL=$work/systemctl \
	DF_USERMOD=$work/usermod \
	"$root/scripts/docker-rootful.sh" \
	--approve-rootful --grant-docker-group >"$work/out"

grep -q '^apt-get update$' "$log"
grep -q '^apt-get install -y docker.io docker-buildx docker-compose-v2$' "$log"
grep -q '^systemctl enable --now docker.service$' "$log"
grep -q '^usermod -aG docker test$' "$log"
grep -q 'root-equivalent' "$work/out"

printf '%s\n' 'rootful: ok'
