#!/bin/sh
set -eu
root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-tool-config.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
# shellcheck source=tests/isolate.sh
. "$root/tests/isolate.sh"
isolate_home "$work/home"
DS_MISE=$(command -v mise) JANET_PATH="$root/src" janet -x strict "$root/tests/tool-config.janet"
