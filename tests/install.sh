#!/bin/sh

set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
real_git=$(command -v git)
real_zsh=$(command -v zsh)
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-install-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM

fail() {
	printf '%s\n' "install test: $*" >&2
	exit 1
}

mkdir -p "$work/bin" "$work/fixture/src/runtime" "$work/fixture/.config/mise" "$work/fixture/scripts" "$work/fixture/src/scripts"
cp "$root/.config/mise/config.toml" "$work/fixture/.config/mise/config.toml"
cp "$root/scripts/install.sh" "$work/fixture/scripts/install.sh"
cat >"$work/fixture/src/scripts/update.sh" <<'SH'
#!/bin/sh
printf '%s\n' update >>"$DS_TEST_LOG"
SH
cat >"$work/fixture/ds" <<'SH'
#!/bin/sh
if [ "${1:-}" = update ]; then
	shift
	exec sh "$(dirname -- "$0")/src/scripts/update.sh" "$@"
fi
printf '%s\n' "$*" >>"$DS_TEST_LOG"
test -x "$DS_JANET" && test -x "$DS_MISE"
if [ "${1:-}" = apply ]; then
	[ -z "${DS_TEST_EXPECT_NVIM:-}" ] || [ "$DS_NVIM_SOURCE" = "$DS_TEST_EXPECT_NVIM" ] || exit 12
	[ "${DS_TEST_APPLY_FAIL:-false}" = false ] || exit 13
fi
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
if [ -n "${DS_TEST_REAL_GIT:-}" ]; then
	exec "$DS_TEST_REAL_GIT" "$@"
fi
[ "$1 $2 $3 $4" = 'clone --depth 1 --branch' ]
expected_ref=main
case "$6" in */ds.git) expected_ref=${DS_SOURCE_REF:-main} ;; esac
[ "$5" = "$expected_ref" ]
printf 'ref %s\n' "$5" >>"$DS_TEST_LOG"
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
export XDG_CONFIG_HOME="$HOME/.config"
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
	sh "$root/scripts/install.sh" --prefix "$prefix" --yes --layer remote --skip docker >/dev/null
	grep -qx 'apply remote --skip docker' "$DS_TEST_LOG" || fail 'apply arguments lost'
	[ "$(cat "$prefix/ds/local-edit")" = keep ] || fail 'local edits changed'
	[ "$(grep -c '^clone ' "$DS_TEST_LOG")" -eq 1 ] || fail 'remote should add only Tmux'
	grep -q '^clone .*tmux.conf.git$' "$DS_TEST_LOG" || fail 'Tmux source missing'
	: >"$DS_TEST_LOG"
	sh "$root/scripts/install.sh" --prefix "$prefix" --yes --layer remote --skip docker >/dev/null
	if grep -Eq '^(clone|compile)' "$DS_TEST_LOG"; then
		fail 'reinstall replaced existing sources or runtime'
	fi
done

: >"$DS_TEST_LOG"
DS_SOURCE_REF=tai/readme sh "$root/scripts/install.sh" \
	--prefix "$work/branch" --no-apply >/dev/null
grep -qx 'ref tai/readme' "$DS_TEST_LOG" || fail 'ds branch was ignored'
grep -qx 'ref main' "$DS_TEST_LOG" || fail 'configuration branch changed'

# CWD determines source, including nested directories.
mkdir -p "$work/local checkout/.git" "$work/local checkout/nested/deep"
cp -R "$work/fixture/." "$work/local checkout/"
mkdir -p "$work/nvim.conf/.git" "$work/tmux.conf/.git"
cd "$work/local checkout/nested/deep"
: >"$DS_TEST_LOG"
sh "$root/scripts/install.sh" --prefix "$work/unused" --yes --no-apply >/dev/null
[ ! -e "$work/unused" ] || fail 'nested invocation cloned another project'
[ -x "$work/local checkout/dist/runtime/bin/linux-x64-musl/janet" ] || fail 'local checkout ignored'
if grep -q '^clone ' "$DS_TEST_LOG"; then fail 'existing siblings replaced'; fi

printf '%s\n' '#!/bin/sh' 'echo old' >"$work/local checkout/dist/runtime/bin/linux-x64-musl/janet"
for condition in DS_TEST_FETCH_FAIL DS_TEST_COMPILE_FAIL; do
	: >"$DS_TEST_LOG"
	if env "$condition=true" sh "$root/scripts/install.sh" --yes --no-apply >/dev/null 2>&1; then
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

# Existing compilers need no privileged packages.
rm "$work/prerequisites/musl-gcc"
cp "$work/bin/musl-gcc" "$work/prerequisites/gcc"
cp "$work/bin/musl-gcc" "$work/prerequisites/cc"
printf '%s\n' certificate >"$work/certificates.crt"
sed "s|/etc/ssl/certs/ca-certificates.crt|$work/certificates.crt|" \
	"$root/scripts/install.sh" >"$work/user-compiler-install.sh"
: >"$DS_TEST_LOG"
PATH="$work/prerequisites" DS_TEST_UID=1000 \
	sh "$work/user-compiler-install.sh" --prefix "$work/user-compiler" >/dev/null
if grep -q '^sudo$' "$DS_TEST_LOG"; then fail 'existing compiler required sudo'; fi
grep -qx compile "$DS_TEST_LOG" || fail 'host compiler was skipped'
grep -qx 'apply core' "$DS_TEST_LOG" || fail 'host compiler skipped apply'

# Exercise updates with real local Git remotes.
export DS_TEST_REAL_GIT="$real_git"
source=$work/update-source
prefix=$work/update-install
mkdir -p "$source/scripts" "$source/src/scripts"
cp -R "$work/fixture/." "$source/"
cp "$root/scripts/install.sh" "$source/scripts/install.sh"
cp "$root/src/scripts/update.sh" "$source/src/scripts/update.sh"
printf '%s\n' dist/ >"$source/.gitignore"
git init -q -b main "$source"
git -C "$source" add .
git -C "$source" -c user.name=Test -c user.email=test@example.invalid \
	-c commit.gpgsign=false commit -qm initial
for name in ds nvim.conf tmux.conf; do
	git clone -q "$source" "$prefix/$name"
done
cat >>"$source/scripts/install.sh" <<'SH'
printf '%s\n' refreshed >>"$DS_TEST_LOG"
SH
git -C "$source" add scripts/install.sh
git -C "$source" -c user.name=Test -c user.email=test@example.invalid \
	-c commit.gpgsign=false commit -qm refresh
before=$(git -C "$prefix/ds" rev-parse HEAD)
: >"$DS_TEST_LOG"
if sh "$root/scripts/install.sh" --prefix "$prefix" --no-apply </dev/null >"$work/update-output" 2>&1; then
	fail 'unattended update skipped confirmation'
fi
grep -q 'use --yes' "$work/update-output" || fail 'unattended diagnostic missing'
[ ! -s "$DS_TEST_LOG" ] || fail 'unconfirmed update changed installation'
for answer in n ''; do
	"$real_zsh" -df "$root/tests/install-confirm.zsh" "$root/scripts/install.sh" "$prefix" "$answer" "$work/prompt-output" || {
		cat "$work/prompt-output"
		fail 'decline prompt failed'
	}
	[ ! -s "$DS_TEST_LOG" ] || fail 'declined update performed setup'
	[ "$(git -C "$prefix/ds" rev-parse HEAD)" = "$before" ] || fail 'decline updated checkout'
done
"$real_zsh" -df "$root/tests/install-confirm.zsh" "$root/scripts/install.sh" "$prefix" y "$work/prompt-output" || {
	cat "$work/prompt-output"
	fail 'accepted prompt failed'
}
[ "$(git -C "$prefix/ds" rev-parse HEAD)" = "$(git -C "$source" rev-parse HEAD)" ] || fail 'accepted update missed checkout'
[ "$(grep -c '^refreshed$' "$DS_TEST_LOG")" -eq 1 ] || fail 'accepted update resumed incorrectly'

for attempt in first repeat; do
	: >"$DS_TEST_LOG"
	sh "$root/scripts/install.sh" --prefix "$prefix" --yes \
		--layer remote --layer extra --force --skip docker --no-apply >"$work/update-output" 2>&1 || {
		cat "$work/update-output"
		fail "installer update failed: $attempt"
	}
	for name in ds nvim.conf tmux.conf; do
		[ "$(git -C "$prefix/$name" rev-parse HEAD)" = "$(git -C "$source" rev-parse HEAD)" ] || fail "update missed $name"
	done
	grep -qx 'apply remote extra --force --skip docker --dry-run' "$DS_TEST_LOG" || fail 'update lost apply options'
	[ "$(grep -c '^refreshed$' "$DS_TEST_LOG")" -eq 1 ] || fail 'updated installer did not resume once'
	if [ "$attempt" = repeat ] && grep -qx compile "$DS_TEST_LOG"; then
		fail 'repeat update rebuilt unchanged runtime'
	fi
done
mkdir -p "$HOME/.local/bin"
ln -s "$prefix/ds/ds" "$HOME/.local/bin/ds"
: >"$DS_TEST_LOG"
sh "$root/scripts/install.sh" --yes --layer extra --no-apply >"$work/update-output" 2>&1 || {
	cat "$work/update-output"
	fail 'installed launcher was not detected'
}
grep -qx refreshed "$DS_TEST_LOG" || fail 'launcher detection selected another checkout'
[ ! -e "$HOME/.local/share/ds-source" ] || fail 'launcher detection cloned another installation'

# Public update refreshes runtimes and selected layers.
mkdir -p "$XDG_CONFIG_HOME/ds"
printf '%s\n' remote,extra >"$XDG_CONFIG_HOME/ds/layer"
mv "$prefix/nvim.conf" "$prefix/custom nvim"
ln -s "$prefix/custom nvim" "$XDG_CONFIG_HOME/nvim"
DS_TEST_EXPECT_NVIM=$(CDPATH='' cd "$prefix/custom nvim" && pwd -P)
export DS_TEST_EXPECT_NVIM
sed 's/DS_JANET_VERSION = "[^"]*"/DS_JANET_VERSION = "1.42.999"/' \
	"$source/.config/mise/config.toml" >"$work/config.toml"
mv "$work/config.toml" "$source/.config/mise/config.toml"
git -C "$source" add .config/mise/config.toml
git -C "$source" -c user.name=Test -c user.email=test@example.invalid \
	-c commit.gpgsign=false commit -qm runtime
: >"$DS_TEST_LOG"
"$prefix/ds/ds" update >"$work/update-output" 2>&1 || {
	cat "$work/update-output"
	fail 'public update failed'
}
grep -qx compile "$DS_TEST_LOG" || fail 'update did not refresh runtime'
[ "$(grep -c '^apply remote extra$' "$DS_TEST_LOG")" -eq 1 ] || fail 'update did not reapply selected layers once'
[ "$(grep -c '^ds update: pulling ' "$work/update-output")" -eq 3 ] || fail 'update repeated repository pulls'
[ "$(grep -c '^refreshed$' "$DS_TEST_LOG")" -eq 1 ] || fail 'update used stale installer'
[ "$(cat "$XDG_CONFIG_HOME/ds/layer")" = remote,extra ] || fail 'update changed selection'
[ ! -e "$prefix/nvim.conf" ] || fail 'update lost custom configuration source'

for failure in runtime apply; do
	: >"$DS_TEST_LOG"
	if [ "$failure" = runtime ]; then
		printf '%s\n' '#!/bin/sh' 'echo old' >"$prefix/ds/dist/runtime/bin/linux-x64-musl/janet"
		condition=DS_TEST_COMPILE_FAIL
	else
		condition=DS_TEST_APPLY_FAIL
	fi
	if env "$condition=true" "$prefix/ds/ds" update >"$work/update-output" 2>&1; then
		fail "update ignored $failure failure"
	fi
	if [ "$failure" = runtime ] && grep -q '^apply ' "$DS_TEST_LOG"; then
		fail 'failed runtime reached apply'
	fi
done
unset DS_TEST_EXPECT_NVIM
rm "$XDG_CONFIG_HOME/ds/layer"

printf '%s\n' keep >"$prefix/ds/local-edit"
: >"$DS_TEST_LOG"
if sh "$root/scripts/install.sh" --prefix "$prefix" --yes --layer extra >"$work/update-output" 2>&1; then
	fail 'dirty update succeeded'
fi
grep -q 'uncommitted changes' "$work/update-output" || fail 'update failure was hidden'
[ "$(cat "$prefix/ds/local-edit")" = keep ] || fail 'dirty update changed local edits'
if grep -Eq '^(apply|mise|compile)' "$DS_TEST_LOG"; then fail 'failed update reached setup'; fi

printf '%s\n' 'install: ok'
