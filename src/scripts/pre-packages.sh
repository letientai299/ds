#!/bin/sh

set -eu

if ! command -v dnf >/dev/null 2>&1; then
	exit 0
fi

if dnf -q info nnn >/dev/null 2>&1; then
	exit 0
fi

if [ "$(id -u)" -eq 0 ]; then
	privilege=
elif command -v sudo >/dev/null 2>&1; then
	privilege=sudo
else
	printf '%s\n' 'ds: enabling CRB and EPEL requires root or sudo' >&2
	exit 1
fi

$privilege dnf -y install dnf-plugins-core epel-release
# dnf5 (Fedora 41+, RHEL 10) removed --set-enabled in favour of setopt.
$privilege dnf config-manager --set-enabled crb 2>/dev/null ||
	$privilege dnf config-manager setopt crb.enabled=1
$privilege dnf -y makecache
