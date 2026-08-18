#!/bin/sh

set -eu

die() {
	printf '%s\n' "docker-rootful: $*" >&2
	exit 1
}

[ "${1:-}" = --approve-rootful ] || die 'requires --approve-rootful'
[ "${2:-}" = --grant-docker-group ] || die 'requires --grant-docker-group (root-equivalent access)'
[ -n "${DF_TARGET_USER:-}" ] || die 'DF_TARGET_USER is required'

sudo_cmd=${DF_SUDO:-sudo}
apt_get=${DF_APT_GET:-apt-get}
apk=${DF_APK:-apk}
systemctl=${DF_SYSTEMCTL:-systemctl}
service=${DF_SERVICE:-service}
rc_update=${DF_RC_UPDATE:-rc-update}
usermod=${DF_USERMOD:-usermod}
addgroup=${DF_ADDGROUP:-addgroup}

as_root() {
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
	else
		"$sudo_cmd" "$@"
	fi
}

if command -v "$apt_get" >/dev/null 2>&1; then
	as_root "$apt_get" update
	as_root "$apt_get" install -y docker.io docker-buildx docker-compose-v2
	as_root "$systemctl" enable --now docker.service
	as_root "$usermod" -aG docker "$DF_TARGET_USER"
elif command -v "$apk" >/dev/null 2>&1; then
	as_root "$apk" add docker docker-cli-buildx docker-cli-compose
	as_root "$rc_update" add docker default
	as_root "$service" docker start
	as_root "$addgroup" "$DF_TARGET_USER" docker
else
	die 'supported rootful package manager not found (apt-get or apk)'
fi

printf '%s\n' \
	'Rootful Docker installed with root-equivalent docker-group access.' \
	'Log out and back in before running ds doctor remote.'
