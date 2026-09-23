#!/bin/sh

set -eu

while [ "$#" -gt 0 ]; do
	case "$1" in
	-o) shift 2 ;;
	-O) exit 0 ;;
	*) break ;;
	esac
done
[ "$#" -eq 2 ] || exit 2
if [ -n "${DS_SSH_LOG:-}" ]; then
	printf '%s\n' "$2" >>"$DS_SSH_LOG"
fi
if [ -n "${DS_SSH_DELAY:-}" ]; then
	sleep "$DS_SSH_DELAY"
fi
if [ "${DS_SSH_NO_TAR:-false}" = true ] && [ "$2" = 'command -v tar' ]; then
	exit 1
fi
cd "$DS_FAKE_REMOTE_HOME"
HOME=$DS_FAKE_REMOTE_HOME exec /bin/sh -c "$2"
