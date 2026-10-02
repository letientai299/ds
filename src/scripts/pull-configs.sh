#!/bin/sh

set -eu

die() {
	printf '%s\n' "ds upgrade: $*" >&2
	exit 1
}

root=$(CDPATH='' cd -P "$(dirname -- "$0")/../.." && pwd)
# shellcheck source=src/scripts/repos.sh
. "$root/src/scripts/repos.sh"
pull_repositories "$root" 'ds upgrade'
