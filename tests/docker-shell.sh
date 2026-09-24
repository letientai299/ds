#!/bin/sh
set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-docker-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM
fail() {
	printf '%s\n' "docker shell test: $*" >&2
	exit 1
}
mkdir -p "$work/checkout/src/bundle" "$work/bin" "$work/tmp" "$work/work, \"quoted\""
cp "$root/ds" "$work/checkout/ds"
cp "$root/src/bundle/docker.sh" "$root/src/bundle/Dockerfile" "$work/checkout/src/bundle/"
ln -s "$work/checkout/ds" "$work/bin/ds"
cat >"$work/checkout/src/bundle/build.sh" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' snapshot >>"$DS_TEST_STATE/calls"
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output ]; then
    mkdir -p "$2"
    printf '%s\n' fixture >"$2/manifest.sha256"
  fi
  shift
done
SH
cat >"$work/bin/docker" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$1" >>"$DS_TEST_STATE/calls"
printf '%s\n' "$@" >"$DS_TEST_STATE/$1.args"
case "$1" in
info) printf '%s\n' "linux/${DS_TEST_ARCH:-aarch64}" ;;
image) test -f "$DS_TEST_STATE/image" ;;
build)
  for arg do context=$arg; done
  test -f "$context/snapshot/manifest.sha256"
  test -f "$context/Dockerfile"
  [ "${DS_TEST_BUILD_STATUS:-0}" = 0 ] || exit "$DS_TEST_BUILD_STATUS"
  touch "$DS_TEST_STATE/image"
  ;;
run) exit "${DS_TEST_RUN_STATUS:-0}" ;;
*) exit 90 ;;
esac
SH
chmod +x "$work/checkout/ds" "$work/checkout/src/bundle/"*.sh "$work/bin/docker"
export DS_TEST_STATE="$work" PATH="$work/bin:$PATH" TMPDIR="$work/tmp"
export DS_RUNTIME_DIST="$work/runtime" DS_JANET=/missing-runtime
unset DS_DOCKER_IMAGE
for platform in linux-arm64-musl linux-x64-musl; do
	mkdir -p "$DS_RUNTIME_DIST/bin/$platform"
	for binary in janet mise; do
		printf '%s\n' '#!/bin/sh' 'exit 0' >"$DS_RUNTIME_DIST/bin/$platform/$binary"
		chmod +x "$DS_RUNTIME_DIST/bin/$platform/$binary"
	done
done
cd "$work/work, \"quoted\""
ds docker --help >"$work/help"
test ! -e "$work/calls" || fail 'help contacted Docker'
if ds docker --bad >"$work/out" 2>&1; then fail 'unknown option accepted'; fi
ds docker
grep -qx 'ds-local:core-arm64' "$work/build.args" || fail 'wrong image'
grep -qx -- '--pull' "$work/build.args" || fail 'base image not refreshed'
grep -qx -- '--rm' "$work/run.args" || fail 'container not disposable'
grep -qx -- '/work' "$work/run.args" || fail 'wrong working directory'
mount_source=$(pwd -P | sed 's/"/""/g')
grep -Fqx "type=bind,\"source=$mount_source\",target=/work" "$work/run.args" || fail 'mount quoting lost'
[ -z "$(ls -A "$work/tmp")" ] || fail 'build context leaked'
mv "$work/checkout/src/bundle/build.sh" "$work/builder"
ds docker -- printf '%s' 'argument with spaces'
[ "$(grep -cx build "$work/calls")" -eq 1 ] || fail 'cache rebuilt'
[ "$(grep -cx snapshot "$work/calls")" -eq 1 ] || fail 'cache repacked snapshot'
grep -qx 'argument with spaces' "$work/run.args" || fail 'command argument split'
mv "$work/builder" "$work/checkout/src/bundle/build.sh"
ds docker --rebuild -- true
[ "$(grep -cx build "$work/calls")" -eq 2 ] || fail 'refresh skipped'
before=$(grep -cx run "$work/calls")
if DS_TEST_BUILD_STATUS=8 ds docker --rebuild; then fail 'build failure hidden'; fi
[ "$(grep -cx run "$work/calls")" -eq "$before" ] || fail 'ran stale image after failure'
[ -z "$(ls -A "$work/tmp")" ] || fail 'failed build leaked context'
DS_TEST_RUN_STATUS=37 ds docker -- false && code=0 || code=$?
[ "$code" -eq 37 ] || fail 'container exit status lost'
DS_TEST_ARCH=x86_64 ds docker
grep -qx 'ds-local:core-amd64' "$work/run.args" || fail 'engine architecture ignored'
cp -R "$root/src/scripts" "$work/checkout/src/scripts"
cp "$root/src/bundle/controller.sh" "$work/checkout/src/bundle/controller.sh"
DS_JANET=$(command -v janet)
export DS_JANET
before=$(wc -l <"$work/calls")
ds shell --docker --help >"$work/help"
[ "$(wc -l <"$work/calls")" -eq "$before" ] || fail 'shell help contacted Docker'
ds shell --docker -- printf '%s' 'argument with spaces' --help --docker
grep -qx 'argument with spaces' "$work/run.args" || fail 'shell argument split'
grep -qx -- --help "$work/run.args" || fail 'command help intercepted'
grep -qx -- --docker "$work/run.args" || fail 'command option consumed'
ds shell --rebuild --docker -- true
[ "$(grep -cx build "$work/calls")" -eq 4 ] || fail 'shell rebuild skipped'
DS_TEST_RUN_STATUS=38 ds shell --docker -- false && code=0 || code=$?
[ "$code" -eq 38 ] || fail 'shell exit status lost'
rm "$work/checkout/src/bundle/controller.sh"
ds --help >"$work/target-help"
if grep -q -- --docker "$work/target-help"; then fail 'target advertises Docker shell'; fi
ds help --all >"$work/target-help"
if grep -Eq '^  (push|docker) ' "$work/target-help"; then fail 'target advertises controller commands'; fi
ds shell --help >"$work/target-help"
if grep -q -- --docker "$work/target-help"; then fail 'target shell help advertises Docker'; fi
ds completion bash >"$work/target-completion"
if grep -Eq '(push\)|docker\)|--docker)' "$work/target-completion"; then fail 'target completion advertises controller commands'; fi
before=$(wc -l <"$work/calls")
if ds shell --docker >"$work/out" 2>"$work/err"; then fail 'target accepted Docker shell'; fi
[ "$(wc -l <"$work/calls")" -eq "$before" ] || fail 'target contacted Docker'
grep -q 'requires a controller checkout' "$work/err" || fail 'controller diagnostic absent'
printf '%s\n' 'docker shell: ok'
