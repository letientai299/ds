#!/bin/sh

set -eu

has_command() {
	if command -v "$1" >/dev/null 2>&1; then
		printf '%s\tpresent\n' "$1"
	else
		printf '%s\tmissing\n' "$1"
	fi
}

os=$(uname -s)
arch=$(uname -m)
uid=$(id -u)
user=$(id -un)

printf 'os\t%s\n' "$os"
printf 'arch\t%s\n' "$arch"
printf 'uid\t%s\n' "$uid"
printf 'user\t%s\n' "$user"
for command in sh mkdir cat chmod curl wget git zsh systemctl docker dockerd-rootless-setuptool.sh newuidmap newgidmap; do
	has_command "$command"
done

if [ -r /etc/subuid ] && awk -F : -v user="$user" -v uid="$uid" '$1 == user || $1 == uid { found = 1 } END { exit !found }' /etc/subuid; then
	printf 'subuid\tpresent\n'
else
	printf 'subuid\tmissing\n'
fi
if [ -r /etc/subgid ] && awk -F : -v user="$user" -v uid="$uid" '$1 == user || $1 == uid { found = 1 } END { exit !found }' /etc/subgid; then
	printf 'subgid\tpresent\n'
else
	printf 'subgid\tmissing\n'
fi
if [ -d "/run/user/$uid" ]; then
	printf 'runtime_dir\tpresent\n'
else
	printf 'runtime_dir\tmissing\n'
fi
if [ -e "/var/lib/systemd/linger/$user" ]; then
	printf 'linger\tpresent\n'
else
	printf 'linger\tmissing\n'
fi
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
	printf 'docker_daemon\tready\n'
else
	printf 'docker_daemon\tunavailable\n'
fi
