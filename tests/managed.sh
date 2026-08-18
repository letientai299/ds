#!/bin/sh

set -eu

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-managed.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

DS_TEST_HOME=$work/home DS_ROOT=$root DS_MISE=$(command -v mise) JANET_PATH=$root/src janet "$root/tests/managed.janet"
