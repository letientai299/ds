#!/bin/sh

set -eu

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-rootful.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail() {
	printf '%s\n' "rootful: $*" >&2
	exit 1
}

printf '%s\n' '#!/bin/sh' 'exec "$@"' >"$work/sudo"
chmod 0755 "$work/sudo"

# Every branch is driven through fakes, so the package manager a case selects is
# decided purely by which fake binaries its PATH-independent overrides name.
fake() {
	# shellcheck disable=SC2016 # The log line is expanded by the fake, not here.
	printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$(basename "$0") $*" >>"$DS_ROOTFUL_LOG"' >"$work/$1"
	chmod 0755 "$work/$1"
}
for name in apt-get apk dnf systemctl service rc-update usermod addgroup; do
	fake "$name"
done
# Every case points the package managers it is not exercising at this path, so
# that `command -v` fails for them and the branch under test is the one taken.
absent=$work/absent

if env DS_TARGET_USER=test "$root/src/scripts/docker-rootful.sh" >"$work/refused.out" 2>&1; then
	fail 'missing approvals were accepted'
fi

# run_case <name> [per-case override ...]
run_case() {
	name=$1
	shift
	log=$work/log-$name
	: >"$log"
	env DS_ROOTFUL_LOG="$log" \
		DS_TARGET_USER=test \
		DS_SUDO="$work/sudo" \
		DS_APT_GET="$absent" \
		DS_APK="$absent" \
		DS_DNF="$absent" \
		DS_SYSTEMCTL="$work/systemctl" \
		DS_SERVICE="$work/service" \
		DS_RC_UPDATE="$work/rc-update" \
		DS_USERMOD="$work/usermod" \
		DS_ADDGROUP="$work/addgroup" \
		DS_DOCKER_REPO="file://$work/docker-ce.repo" \
		"$@" \
		"$root/src/scripts/docker-rootful.sh" \
		--approve-rootful --grant-docker-group >"$work/out-$name" ||
		fail "$name branch exited non-zero"
	grep -q 'root-equivalent' "$work/out-$name" || fail "$name branch printed no group warning"
}

expect() {
	grep -qx "$2" "$work/log-$1" || fail "$1 branch is missing: $2"
}

run_case apt DS_APT_GET="$work/apt-get"
expect apt 'apt-get update'
expect apt 'apt-get install -y docker.io docker-buildx docker-compose-v2'
expect apt 'systemctl enable --now docker.service'
expect apt 'usermod -aG docker test'

run_case apk DS_APK="$work/apk"
expect apk 'apk add docker docker-cli-buildx docker-cli-compose'
expect apk 'rc-update add docker default'
expect apk 'service docker start'
expect apk 'addgroup test docker'

run_case dnf DS_DNF="$work/dnf"
expect dnf 'dnf -y install dnf-plugins-core'
expect dnf "dnf config-manager --add-repo file://$work/docker-ce.repo"
expect dnf 'dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin'
expect dnf 'systemctl enable --now docker.service'
expect dnf 'usermod -aG docker test'

if env DS_ROOTFUL_LOG="$work/log-none" \
	DS_TARGET_USER=test \
	DS_SUDO="$work/sudo" \
	DS_APT_GET="$absent" \
	DS_APK="$absent" \
	DS_DNF="$absent" \
	"$root/src/scripts/docker-rootful.sh" \
	--approve-rootful --grant-docker-group >"$work/none.out" 2>&1; then
	fail 'a host with no supported package manager was accepted'
fi
grep -q 'apt-get, apk, or dnf' "$work/none.out" || fail 'the unsupported-host message does not list the branches'

printf '%s\n' 'rootful: ok'
