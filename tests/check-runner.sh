#!/bin/sh

set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-check-runner.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM
mkdir -p "$work/tests" "$work/src/runtime"
cp "$root/tests/check.sh" "$root/tests/isolate.sh" "$work/tests/"
export DS_RUNNER_CALLS="$work/calls" DS_CHECK_JOBS=1 DS_CORE_CASES=native
export DS_SHELL_SOURCES=unused

cat >"$work/stub" <<'SH'
#!/bin/sh
printf '%s %s\n' "${0##*/}" "$*" >>"$DS_RUNNER_CALLS"
[ -z "${DS_RUNNER_FAIL:-}" ] || [ "$DS_RUNNER_FAIL" != "$*" ]
SH
chmod +x "$work/stub"
for script in core remote layer container controller docker-readiness; do
	cp "$work/stub" "$work/tests/$script.sh"
done
for script in fetch fetch-mise build; do
	cp "$work/stub" "$work/src/runtime/$script.sh"
done

run() {
	: >"$DS_RUNNER_CALLS"
	sh "$work/tests/check.sh" "$@" >"$work/output" 2>&1
}

run docker-readiness
[ "$(wc -l <"$DS_RUNNER_CALLS")" -eq 1 ]
grep -qx 'docker-readiness.sh ' "$DS_RUNNER_CALLS"
run core
[ "$(grep -c '^build.sh ' "$DS_RUNNER_CALLS")" -eq 1 ]
grep -qx 'core.sh ' "$DS_RUNNER_CALLS"
run containers
[ "$(grep -c '^build.sh ' "$DS_RUNNER_CALLS")" -eq 2 ]
grep -qx 'build.sh linux-arm64-musl' "$DS_RUNNER_CALLS"
grep -qx 'build.sh linux-x64-musl' "$DS_RUNNER_CALLS"
(DS_CORE_CASES=all run core)
[ "$(grep -c '^build.sh ' "$DS_RUNNER_CALLS")" -eq 2 ]
run core remote
[ "$(grep -c '^layer.sh core-remote$' "$DS_RUNNER_CALLS")" -eq 1 ]
[ "$(wc -l <"$DS_RUNNER_CALLS")" -eq 4 ]
run e2e core remote
[ "$(grep -c '^layer.sh core-remote$' "$DS_RUNNER_CALLS")" -eq 1 ]
[ "$(wc -l <"$DS_RUNNER_CALLS")" -eq 9 ]
if DS_RUNNER_FAIL=core-remote run e2e; then
	printf '%s\n' 'runner hid a failed layer check' >&2
	exit 1
fi
grep -q '^check: 1 failed' "$work/output"
grep -qx 'controller.sh ' "$DS_RUNNER_CALLS"
grep -qx 'docker-readiness.sh ' "$DS_RUNNER_CALLS"
printf '%s\n' 'check runner: ok'
