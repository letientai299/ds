#!/bin/sh

set -eu

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-managed.XXXXXX")
# shellcheck source=tests/isolate.sh
. "$(dirname -- "$0")/isolate.sh"
isolate_home "$work/isolated-home"
trap 'rm -rf "$work"' EXIT HUP INT TERM

DS_TEST_HOME=$work/home DS_ROOT=$root DS_MISE=$(command -v mise) JANET_PATH=$root/src janet "$root/tests/managed.janet"
(
	cd "$work"
	HOME="$work/home/migration" MISE_CONFIG_DIR="$work/home/migration/config/ds/mise" MISE_ENV=ds,core \
		mise config ls --json >"$work/config-list"
	HOME="$work/home/migration" MISE_CONFIG_DIR="$work/home/migration/config/ds/mise" MISE_ENV=ds,core \
		mise set -g DS_TEST_SETTING=local
)
grep -q 'config.ds.toml' "$work/config-list"
grep -q 'npm:git-open' "$work/config-list"
grep -q 'config.core.toml' "$work/config-list"
[ ! -L "$work/home/migration/config/ds/mise/config.toml" ]
grep -q 'DS_TEST_SETTING = "local"' "$work/home/migration/config/ds/mise/config.toml"
! grep -q DS_TEST_SETTING "$root/src/mise/mise.toml"
