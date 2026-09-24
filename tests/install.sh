#!/bin/sh

set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-install-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM

fail() {
	printf '%s\n' "install test: $*" >&2
	exit 1
}

mkdir -p "$work/bin" "$work/fixture/src/runtime" "$work/fixture/.config/mise"
cp "$root/.config/mise/config.toml" "$work/fixture/.config/mise/config.toml"
cat >"$work/fixture/ds" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DS_TEST_LOG"
test -x "$DS_JANET" && test -x "$DS_MISE"
[ "$*" != 'completion zsh' ] || printf '%s\n' '#compdef ds'
SH
cat >"$work/fixture/src/runtime/fetch-mise.sh" <<'SH'
#!/bin/sh
set -eu
printf 'mise %s\n' "$1" >>"$DS_TEST_LOG"
mkdir -p "$DS_RUNTIME_DIST/bin/$1"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$DS_RUNTIME_DIST/bin/$1/mise"
chmod 0755 "$DS_RUNTIME_DIST/bin/$1/mise"
SH
cat >"$work/fixture/src/runtime/fetch.sh" <<'SH'
#!/bin/sh
set -eu
[ "${DS_TEST_FETCH_FAIL:-false}" = false ] || exit 9
printf '%s\n' "$DS_RUNTIME_DIST/src"
SH
cat >"$work/bin/musl-gcc" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' compile >>"$DS_TEST_LOG"
[ "${DS_TEST_COMPILE_FAIL:-false}" = false ] || exit 8
while [ "$1" != -o ]; do shift; done
printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$DS_JANET_VERSION-fixture" >"$2"
SH
cat >"$work/fixture/src/runtime/build.sh" <<'SH'
#!/bin/sh
set -eu
musl-gcc -o "$DS_RUNTIME_DIST/bin/$1/janet"
chmod 0755 "$DS_RUNTIME_DIST/bin/$1/janet"
SH
cat >"$work/bin/uname" <<'SH'
#!/bin/sh
case "$1" in
-s) printf '%s\n' "$DS_TEST_OS" ;;
-m) printf '%s\n' "$DS_TEST_ARCH" ;;
esac
SH
cat >"$work/bin/git" <<'SH'
#!/bin/sh
set -eu
[ "$1 $2 $3 $4 $5" = 'clone --depth 1 --branch main' ]
printf 'clone %s\n' "$6" >>"$DS_TEST_LOG"
[ "${DS_TEST_CLONE_FAIL:-false}" = false ] || exit 7
case "$6" in
*/ds.git) cp -R "$DS_TEST_FIXTURE/." "$7/" ;;
esac
mkdir -p "$7/.git"
SH
for command in xcrun brew xz make curl; do
	printf '%s\n' '#!/bin/sh' 'exit 0' >"$work/bin/$command"
done
cat >"$work/bin/apt-get" <<'SH'
#!/bin/sh
printf 'apt %s\n' "$*" >>"$DS_TEST_LOG"
SH
cat >"$work/bin/id" <<'SH'
#!/bin/sh
printf '%s\n' "${DS_TEST_UID:-0}"
SH
cat >"$work/bin/sudo" <<'SH'
#!/bin/sh
printf '%s\n' sudo >>"$DS_TEST_LOG"
exec "$@"
SH
cat >"$work/bin/zsh" <<'SH'
#!/bin/sh
printf 'shell %s\n' "$*" >>"$DS_TEST_LOG"
SH
chmod 0755 "$work/bin/"* "$work/fixture/ds"
export PATH="$work/bin:$PATH" DS_TEST_FIXTURE="$work/fixture"
export DS_TEST_LOG="$work/actions"
export HOME="$work/home"
unset DS_NVIM_SOURCE DS_TMUX_SOURCE DS_KITTY_SOURCE

cd "$work"
: >"$DS_TEST_LOG"
sh "$root/scripts/install.sh" --help >/dev/null
[ ! -s "$DS_TEST_LOG" ] || fail 'help performed setup'
for args in '--layer invalid' '--skip git' '--no-apply --shell' '--source nowhere' '--prefix'; do
	# Arguments deliberately exercise parser splitting.
	# shellcheck disable=SC2086
	if sh "$root/scripts/install.sh" $args >/dev/null 2>&1; then
		fail "invalid arguments accepted: $args"
	fi
done

for target in Darwin:arm64:macos-arm64 Darwin:x86_64:macos-x64 Linux:aarch64:linux-arm64-musl Linux:x86_64:linux-x64-musl; do
	DS_TEST_OS=${target%%:*}
	rest=${target#*:}
	DS_TEST_ARCH=${rest%%:*}
	platform=${rest#*:}
	export DS_TEST_OS DS_TEST_ARCH
	prefix=$work/$platform
	: >"$DS_TEST_LOG"
	sh "$root/scripts/install.sh" --prefix "$prefix" --no-apply >/dev/null
	grep -qx "mise $platform" "$DS_TEST_LOG" || fail 'wrong runtime platform'
	grep -qx 'diff core' "$DS_TEST_LOG" || fail 'preview diff missing'
	grep -qx 'apply core --dry-run' "$DS_TEST_LOG" || fail 'preview applied changes'
	grep -qx 'completion zsh' "$DS_TEST_LOG" || fail 'completion was not generated'
	grep -qx '#compdef ds' "$HOME/.local/share/zsh/site-functions/_ds" || fail 'completion missing'
	[ "$(grep -c '^clone ' "$DS_TEST_LOG")" -eq 2 ] || fail 'core should clone only ds and Neovim'
	[ "$(grep -c '^compile$' "$DS_TEST_LOG")" -eq 1 ] || fail 'runtime not built'
	printf '%s\n' keep >"$prefix/ds/local-edit"
	: >"$DS_TEST_LOG"
	sh "$root/scripts/install.sh" --prefix "$prefix" --layer remote --skip docker >/dev/null
	grep -qx 'apply remote --skip docker' "$DS_TEST_LOG" || fail 'apply arguments lost'
	[ "$(cat "$prefix/ds/local-edit")" = keep ] || fail 'local edits changed'
	[ "$(grep -c '^clone ' "$DS_TEST_LOG")" -eq 1 ] || fail 'remote should add only Tmux'
	grep -q '^clone .*tmux.conf.git$' "$DS_TEST_LOG" || fail 'Tmux source missing'
	: >"$DS_TEST_LOG"
	sh "$root/scripts/install.sh" --prefix "$prefix" --layer remote --skip docker >/dev/null
	if grep -Eq '^(clone|compile)' "$DS_TEST_LOG"; then
		fail 'reinstall replaced existing sources or runtime'
	fi
done

# CWD determines source, including nested directories.
mkdir -p "$work/local checkout/.git" "$work/local checkout/nested/deep"
cp -R "$work/fixture/." "$work/local checkout/"
mkdir -p "$work/nvim.conf/.git" "$work/tmux.conf/.git"
cd "$work/local checkout/nested/deep"
: >"$DS_TEST_LOG"
sh "$root/scripts/install.sh" --prefix "$work/unused" --no-apply >/dev/null
[ ! -e "$work/unused" ] || fail 'nested invocation cloned another project'
[ -x "$work/local checkout/dist/runtime/bin/linux-x64-musl/janet" ] || fail 'local checkout ignored'
if grep -q '^clone ' "$DS_TEST_LOG"; then fail 'existing siblings replaced'; fi

printf '%s\n' '#!/bin/sh' 'echo old' >"$work/local checkout/dist/runtime/bin/linux-x64-musl/janet"
for condition in DS_TEST_FETCH_FAIL DS_TEST_COMPILE_FAIL; do
	: >"$DS_TEST_LOG"
	if env "$condition=true" sh "$root/scripts/install.sh" --no-apply >/dev/null 2>&1; then
		fail 'runtime failure was ignored'
	fi
	if grep -Eq '^(diff|apply)' "$DS_TEST_LOG"; then fail 'failed runtime reached apply'; fi
	[ -z "$(find "$work/local checkout" -name '*.part.*' -print)" ] || fail 'partial runtime leaked'
	[ "$("$work/local checkout/dist/runtime/bin/linux-x64-musl/janet")" = old ] || fail 'failed build replaced runtime'
done

cd "$work"
if DS_TEST_CLONE_FAIL=true sh "$root/scripts/install.sh" --prefix "$work/failed clone" >/dev/null 2>&1; then
	fail 'clone failure was ignored'
fi
[ ! -e "$work/failed clone/ds" ] || fail 'failed clone published checkout'
[ -z "$(find "$work/failed clone" -name '*.clone.*' -print)" ] || fail 'partial clone leaked'

mkdir -p "$work/prerequisites"
cp "$work/bin/"* "$work/prerequisites/"
rm "$work/prerequisites/musl-gcc"
for command in dirname mkdir mktemp cp mv rm sed chmod tar sh; do
	ln -s "$(command -v "$command")" "$work/prerequisites/$command"
done
cat >"$work/prerequisites/apt-get" <<'SH'
#!/bin/sh
set -eu
printf 'apt %s\n' "$*" >>"$DS_TEST_LOG"
if [ "$1" = install ]; then
	cp "$DS_TEST_COMPILER" "$(dirname -- "$0")/musl-gcc"
fi
SH
: >"$DS_TEST_LOG"
PATH="$work/prerequisites" DS_TEST_UID=1000 DS_TEST_COMPILER="$work/bin/musl-gcc" \
	sh "$root/scripts/install.sh" --prefix "$work/nonroot" --shell >/dev/null
[ "$(grep -c '^sudo$' "$DS_TEST_LOG")" -eq 2 ] || fail 'prerequisites bypassed sudo'
grep -qx 'apply core' "$DS_TEST_LOG" || fail 'shell skipped apply'
[ "$(tail -1 "$DS_TEST_LOG")" = 'shell -l' ] || fail 'shell started before apply'

printf '%s\n' 'install: ok'
