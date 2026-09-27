#!/bin/sh

# Runs check steps concurrently. Arguments pick groups or single steps and
# default to static, unit, and contract. Each step logs to its own file;
# failed logs print after the run.

set -eu

die() {
	printf '%s\n' "ds check: $*" >&2
	exit 1
}

steps() {
	cat <<'EOF'
static	shellcheck	shellcheck -x $DS_SHELL_SOURCES
static	shfmt	shfmt -d $DS_SHELL_SOURCES
static	zsh-syntax	zsh -fc 'for source in src/dotfiles/**/*.zsh src/tools/fzf-* src/dotfiles/completions/* tests/*.zsh; do zsh -n "$source" || exit; done'
static	taplo	taplo fmt --check .config/mise/config.toml src/catalog.toml src/mise/*.toml
static	generate	src/scripts/generate.sh --check
unit	janet-lint	for source in src/scripts/generated/*.janet src/scripts/lib/*.janet; do JANET_PATH=$PWD/src janet -x strict "$source" || exit; done
unit	status	DS_MISE=$(command -v mise) DS_ROOT=$PWD JANET_PATH=$PWD/src janet -x strict src/scripts/main.janet status core >/dev/null
unit	harness	JANET_PATH=$PWD/src janet -x strict tests/harness.janet
unit	layers	JANET_PATH=$PWD/src janet -x strict tests/layers.janet
unit	mise	JANET_PATH=$PWD/src janet -x strict tests/mise.janet
unit	docker	JANET_PATH=$PWD/src janet -x strict tests/docker.janet
unit	platform	JANET_PATH=$PWD/src janet -x strict tests/platform.janet
unit	selection	home=$(mktemp -d "${TMPDIR:-/tmp}/ds-selection.XXXXXX"); trap 'rm -rf "$home"' EXIT; DS_TEST_HOME=$home JANET_PATH=$PWD/src janet -x strict tests/selection.janet
unit	managed	tests/managed.sh
unit	rootful	tests/rootful.sh
unit	runtime-build	sh tests/runtime-build.sh
unit	install	sh tests/install.sh
unit	update	sh tests/update.sh
unit	shell-init	sh tests/shell-init.sh
unit	shell	sh tests/shell.sh
unit	aliases	sh tests/aliases.sh
unit	plugins	sh tests/plugins.sh
unit	prompt	zsh -df tests/prompt.zsh
unit	tools	sh tests/tools.sh
unit	exports	sh tests/exports.sh
unit	navigation	sh tests/navigation.sh
unit	activation	sh tests/activation.sh
unit	independent-layers	sh tests/independent-layers.sh
unit	ux	sh tests/ux.sh
unit	decisions	sh tests/decisions.sh
unit	checksum	sh tests/checksum.sh
unit	push	sh tests/push.sh
unit	try	sh tests/try.sh
unit	docker-shell	sh tests/docker-shell.sh
unit	check-runner	sh tests/check-runner.sh
contract	contract	DS_ROOT=$PWD DS_JANET=$(command -v janet) tests/contract.sh
e2e	containers	tests/container.sh
e2e	controller	tests/controller.sh
layer	core	tests/core.sh
layer	remote	tests/remote.sh
layer	core-remote-extra	sh tests/layer.sh core-remote-extra
e2e	core-remote	sh tests/layer.sh core-remote
e2e	docker-readiness	tests/docker-readiness.sh
bench	bench-linux	tests/performance-linux.sh
EOF
}

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
cd "$root"

# xargs re-enters here once per step.
if [ "${1:-}" = --step ]; then
	name=$2
	command=$(steps | awk -F '\t' -v name="$name" '$2 == name { print $3 }')
	# shellcheck source=tests/isolate.sh
	. "$root/tests/isolate.sh"
	isolate_home "$DS_CHECK_LOGS/$name.home"
	started=$(date +%s)
	if sh -c "$command" >"$DS_CHECK_LOGS/$name.log" 2>&1 </dev/null; then
		printf 'ok    %4ss  %s\n' "$(($(date +%s) - started))" "$name"
		exit 0
	fi
	printf 'FAIL  %4ss  %s\n' "$(($(date +%s) - started))" "$name"
	: >"$DS_CHECK_LOGS/$name.failed"
	exit 1
fi

[ "$#" -gt 0 ] || set -- static unit contract
for selector in "$@"; do
	steps | awk -F '\t' -v s="$selector" '$1 == s || $2 == s { found = 1 } END { exit !found }' ||
		die "unknown group or step: $selector"
done
: "${DS_SHELL_SOURCES:?run through mise so DS_SHELL_SOURCES is set}"

DS_CHECK_LOGS=$(mktemp -d "${TMPDIR:-/tmp}/ds-check.XXXXXX")
export DS_CHECK_LOGS
trap 'rm -rf "$DS_CHECK_LOGS"' EXIT
trap 'exit 143' HUP INT TERM
jobs=${DS_CHECK_JOBS:-$(getconf _NPROCESSORS_ONLN)}
started=$(date +%s)

# Longest steps start first: containers, then the contract.
selected=$(steps | awk -F '\t' -v selectors=" $* " '
	index(selectors, " " $1 " ") || index(selectors, " " $2 " ") {
		print ($1 == "e2e" || $1 == "layer" || $1 == "bench" ? 0 : $1 == "contract" ? 1 : 2) "\t" $2
	}' | sort -s -n -k1,1)

# Combine explicitly selected layer steps too.
if printf '%s\n' "$selected" | grep -q 'core-remote$' ||
	{ printf '%s\n' "$selected" | grep -q '[[:space:]]core$' &&
		printf '%s\n' "$selected" | grep -q '[[:space:]]remote$'; }; then
	selected=$(printf '%s\n0\tcore-remote\n' "$selected" |
		awk '$2 != "core" && $2 != "remote" && !seen[$2]++')
fi

# Container steps read the Linux runtimes from dist/runtime.
build_runtimes() {
	src/runtime/fetch.sh || return
	for platform in $platforms; do
		src/runtime/fetch-mise.sh "$platform" || return
		src/runtime/build.sh "$platform" || return
	done
}
platforms=
if printf '%s\n' "$selected" | grep -Eq '[[:space:]](containers|controller|core|remote|core-remote|core-remote-extra|bench-linux)$'; then
	case "$(uname -m)" in
	arm64 | aarch64) platforms=linux-arm64-musl ;;
	x86_64 | amd64) platforms=linux-x64-musl ;;
	*) die 'unsupported native architecture' ;;
	esac
	if printf '%s\n' "$selected" | grep -q '[[:space:]]containers$' ||
		[ "${DS_CORE_CASES:-native}" = all ]; then
		platforms='linux-arm64-musl linux-x64-musl'
	fi
fi
if [ -n "$platforms" ]; then
	if ! build_runtimes >"$DS_CHECK_LOGS/runtime.log" 2>&1; then
		cat "$DS_CHECK_LOGS/runtime.log" >&2
		die 'runtime build failed'
	fi
	printf 'ok    %4ss  %s\n' "$(($(date +%s) - started))" runtime
fi

printf '%s\n' "$selected" | cut -f2 | xargs -P "$jobs" -n 1 sh "$0" --step || true

failed=0
for marker in "$DS_CHECK_LOGS"/*.failed; do
	[ -e "$marker" ] || continue
	failed=$((failed + 1))
	name=$(basename "$marker" .failed)
	printf '\n--- %s ---\n' "$name" >&2
	cat "$DS_CHECK_LOGS/$name.log" >&2
done
printf 'check: %s failed in %ss\n' "$failed" "$(($(date +%s) - started))"
[ "$failed" -eq 0 ]
