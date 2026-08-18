#!/bin/sh

set -eu

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/df-managed.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

DF_TEST_HOME=$work/home DF_ROOT=$root DF_MISE=$(command -v mise) JANET_PATH=$root janet "$root/tests/managed.janet"
