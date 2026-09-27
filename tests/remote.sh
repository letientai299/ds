#!/bin/sh

set -eu

exec sh "$(dirname -- "$0")/layer.sh" remote
