#!/bin/sh

set -eu

die() {
	printf '%s\n' "docker-rootful: $*" >&2
	exit 1
}

[ "${1:-}" = --approve-rootful ] || die 'requires --approve-rootful'
[ "${2:-}" = --grant-docker-group ] || die 'requires --grant-docker-group (root-equivalent access)'
[ -n "${DS_TARGET_USER:-}" ] || die 'DS_TARGET_USER is required'

sudo_cmd=${DS_SUDO:-sudo}
apt_get=${DS_APT_GET:-apt-get}
apk=${DS_APK:-apk}
dnf=${DS_DNF:-dnf}
# Docker CE is not in the RHEL or Rocky base repositories, so the dnf branch
# adds Docker's own repository. Overridable so the test can drive it offline.
docker_repo=${DS_DOCKER_REPO:-https://download.docker.com/linux/centos/docker-ce.repo}
systemctl=${DS_SYSTEMCTL:-systemctl}
service=${DS_SERVICE:-service}
rc_update=${DS_RC_UPDATE:-rc-update}
usermod=${DS_USERMOD:-usermod}
addgroup=${DS_ADDGROUP:-addgroup}

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
	as_root "$usermod" -aG docker "$DS_TARGET_USER"
elif command -v "$apk" >/dev/null 2>&1; then
	as_root "$apk" add docker docker-cli-buildx docker-cli-compose
	as_root "$rc_update" add docker default
	as_root "$service" docker start
	as_root "$addgroup" "$DS_TARGET_USER" docker
elif command -v "$dnf" >/dev/null 2>&1; then
	as_root "$dnf" -y install dnf-plugins-core
	# dnf5 (Fedora 41+, RHEL 10) replaced --add-repo with the addrepo subcommand.
	as_root "$dnf" config-manager --add-repo "$docker_repo" 2>/dev/null ||
		as_root "$dnf" config-manager addrepo --from-repofile="$docker_repo"
	as_root "$dnf" -y install docker-ce docker-ce-cli containerd.io \
		docker-buildx-plugin docker-compose-plugin
	as_root "$systemctl" enable --now docker.service
	as_root "$usermod" -aG docker "$DS_TARGET_USER"
else
	die 'supported rootful package manager not found (apt-get, apk, or dnf)'
fi

printf '%s\n' \
	'Rootful Docker installed with root-equivalent docker-group access.' \
	'Log out and back in before running ds doctor remote.'
