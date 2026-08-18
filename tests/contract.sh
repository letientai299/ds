#!/bin/sh

set -eu

root=$(dirname -- "$0")/..
root=$(CDPATH='' cd "$root" && pwd)
janet=${DS_JANET:?DS_JANET must point to Janet 1.41.2}
mise=$(command -v mise)

fail() {
	printf '%s\n' "contract: $*" >&2
	exit 1
}

work=${TMPDIR:-/tmp}/ds-contract-$$
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/bundle/files/bin" "$work/install"

case "$(uname -s):$(uname -m)" in
Darwin:arm64) platform=macos-arm64 ;;
Darwin:x86_64) platform=macos-x64 ;;
Linux:aarch64 | Linux:arm64) platform=linux-arm64-musl ;;
Linux:x86_64 | Linux:amd64) platform=linux-x64-musl ;;
*) fail 'unsupported test platform' ;;
esac

mkdir -p "$work/checkout/dist/runtime/bin/$platform"
cp "$root/ds" "$work/checkout/ds"
# shellcheck disable=SC2016 # Positional argument belongs to the generated fixture.
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$1"' >"$work/checkout/dist/runtime/bin/$platform/janet"
chmod 0755 "$work/checkout/ds" "$work/checkout/dist/runtime/bin/$platform/janet"
checkout_dispatch=$(DS_JANET='' DS_ROOT=$work/checkout "$work/checkout/ds" status core)
[ "$checkout_dispatch" = "$work/checkout/src/scripts/main.janet" ] || fail 'checkout launcher did not use the dist runtime fallback'

printf '%s\n' '#!/bin/sh' 'printf "%s\n" fixture' >"$work/bundle/files/bin/fixture"
fixture_sha=$(shasum -a 256 "$work/bundle/files/bin/fixture" | awk '{print $1}')
tab=$(printf '\t')
printf 'ds-bundle-v1%s0.0.0-test\nfile%s0755%s%s%sbin/fixture\n' \
	"$tab" "$tab" "$tab" "$fixture_sha" "$tab" >"$work/bundle/manifest.tsv"
manifest_sha=$(shasum -a 256 "$work/bundle/manifest.tsv" | awk '{print $1}')

installed=$(
	"$root/src/bootstrap.sh" \
		--source "$work/bundle" \
		--prefix "$work/install" \
		--manifest-sha256 "$manifest_sha"
)
[ "$installed" = "$work/install/versions/0.0.0-test" ] || fail 'unexpected install path'
[ -x "$installed/bin/fixture" ] || fail 'installed fixture is not executable'
[ "$("$installed/bin/fixture")" = fixture ] || fail 'installed fixture did not run'

mkdir -p "$work/tampered/files/bin"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" tampered' >"$work/tampered/files/bin/fixture"
cp "$work/bundle/manifest.tsv" "$work/tampered/manifest.tsv"
if "$root/src/bootstrap.sh" \
	--source "$work/tampered" \
	--prefix "$work/tampered-install" \
	--manifest-sha256 "$manifest_sha" >"$work/tampered.out" 2>"$work/tampered.err"; then
	fail 'tampered bundle unexpectedly installed'
fi
[ ! -e "$work/tampered-install" ] || fail 'tampered bundle left a partial installation'
grep -q 'checksum mismatch' "$work/tampered.err" || fail 'tampered bundle diagnostic is missing'

DS_ROOT=$root DS_JANET=$janet DS_MISE=$mise "$root/ds" apply core --dry-run >"$work/apply.out"
grep -q '^would apply core:$' "$work/apply.out" || fail 'dry-run header is missing'
grep -q '^  neovim$' "$work/apply.out" || fail 'Neovim is missing from core'
HOME=$work/dry-home \
	XDG_CONFIG_HOME=$work/dry-home/config \
	XDG_STATE_HOME=$work/dry-home/state \
	DS_ROOT=$root DS_JANET=$janet DS_MISE=$mise "$root/ds" diff core >"$work/diff.out"
grep -q '^diff core:$' "$work/diff.out" || fail 'diff header is missing'
grep -q '^  + fd$' "$work/diff.out" || fail 'diff does not report a missing managed tool'
grep -q "$work/dry-home/config/nvim" "$work/diff.out" || fail 'diff does not report managed files'
[ ! -e "$work/dry-home" ] || fail 'dry-run or diff wrote to the isolated home'

HOME=$work/dry-remote \
	XDG_CONFIG_HOME=$work/dry-remote/config \
	XDG_STATE_HOME=$work/dry-remote/state \
	DS_ROOT=$root DS_JANET=$janet DS_MISE=$mise \
	"$root/ds" apply remote --dry-run --skip docker >"$work/skip.out"
grep -q '^would apply remote:$' "$work/skip.out" || fail 'remote skip dry-run header is missing'
if grep -q '^  docker$' "$work/skip.out"; then
	fail 'remote skip dry-run still includes Docker'
fi
[ ! -e "$work/dry-remote" ] || fail 'remote skip dry-run wrote to the isolated home'

HOME=$work/dry-optional \
	XDG_CONFIG_HOME=$work/dry-optional/config \
	XDG_STATE_HOME=$work/dry-optional/state \
	DS_ROOT=$root DS_JANET=$janet DS_MISE=$mise \
	"$root/ds" add starship --dry-run >"$work/optional.out"
grep -q '^would add starship$' "$work/optional.out" || fail 'optional dry-run is missing'
[ ! -e "$work/dry-optional" ] || fail 'optional dry-run wrote to the isolated home'

"$root/src/bundle/build.sh" \
	--version 0.0.0-snapshot \
	--platform "$platform" \
	--janet "$janet" \
	--mise "$mise" \
	--output "$work/snapshot" >/dev/null
snapshot_sha=$(sed -n '1p' "$work/snapshot/manifest.sha256")
verified_version=$(
	"$root/src/bootstrap.sh" \
		--source "$work/snapshot" \
		--manifest-sha256 "$snapshot_sha" \
		--verify-only
)
[ "$verified_version" = 0.0.0-snapshot ] || fail 'verify-only returned the wrong version'
snapshot_root=$(
	"$work/snapshot/bootstrap.sh" \
		--source "$work/snapshot" \
		--prefix "$work/snapshot-install" \
		--manifest-sha256 "$snapshot_sha"
)
"$snapshot_root/ds" apply core --dry-run >"$work/snapshot.out"
grep -q '^would apply core:$' "$work/snapshot.out" || fail 'installed snapshot did not dispatch'
[ -x "$snapshot_root/src/runtime/bin/$platform/mise" ] || fail 'snapshot is missing mise'
[ -f "$snapshot_root/src/vendor/nvim.conf/init.lua" ] || fail 'snapshot is missing nvim.conf'
[ -f "$snapshot_root/src/vendor/tmux.conf/tmux.conf" ] || fail 'snapshot is missing tmux.conf'
[ -f "$snapshot_root/src/dotfiles/shell.zsh" ] || fail 'snapshot is missing shell configuration'

pull_root=$(
	"$root/src/pull.sh" \
		--url "file://$work/snapshot" \
		--prefix "$work/pull-install" \
		--manifest-sha256 "$snapshot_sha"
)
"$pull_root/ds" status core >"$work/pull.out"
grep -q '^core: ' "$work/pull.out" || fail 'pull transport did not dispatch'

export DS_TEST_CURL
DS_TEST_CURL=$(command -v curl)
printf '%s\n' \
	'#!/bin/sh' \
	'shift' \
	'shift' \
	"output=\$1" \
	"url=\$2" \
	"exec \"\$DS_TEST_CURL\" -fsSL --output \"\$output\" \"\$url\"" >"$work/fake-wget"
chmod 0755 "$work/fake-wget"
wget_pull_root=$(
	DS_DOWNLOADER=wget DS_WGET=$work/fake-wget "$root/src/pull.sh" \
		--url "file://$work/snapshot" \
		--prefix "$work/wget-pull-install" \
		--manifest-sha256 "$snapshot_sha"
)
"$wget_pull_root/ds" status core >"$work/wget-pull.out"
grep -q '^core: ' "$work/wget-pull.out" || fail 'wget pull transport did not dispatch'

mkdir -p "$work/remote-home"
export DS_FAKE_REMOTE_HOME="$work/remote-home"
printf '%s\n' \
	'#!/bin/sh' \
	'shift' \
	"HOME=\$DS_FAKE_REMOTE_HOME exec /bin/sh -c \"\$1\"" >"$work/fake-ssh"
chmod 0755 "$work/fake-ssh"
push_root=$(
	DS_SSH=$work/fake-ssh "$root/src/bundle/push.sh" \
		--snapshot "$work/snapshot" \
		--host fixture
)
"$push_root/ds" status core >"$work/push.out"
grep -q '^core: ' "$work/push.out" || fail 'SSH push transport did not dispatch'

"$root/src/bundle/pack.sh" --snapshot "$work/snapshot" --output "$work/manual-1.tar.gz" >/dev/null
"$root/src/bundle/pack.sh" --snapshot "$work/snapshot" --output "$work/manual-2.tar.gz" >/dev/null
[ "$(shasum -a 256 "$work/manual-1.tar.gz" | awk '{print $1}')" = \
	"$(shasum -a 256 "$work/manual-2.tar.gz" | awk '{print $1}')" ] || fail 'manual bundle is not reproducible'
mkdir -p "$work/manual"
tar -xzf "$work/manual-1.tar.gz" -C "$work/manual"
manual_root=$(
	"$work/manual/ds-0.0.0-snapshot/bootstrap.sh" \
		--source "$work/manual/ds-0.0.0-snapshot" \
		--prefix "$work/manual-install" \
		--manifest-sha256 "$snapshot_sha"
)
"$manual_root/ds" status core >"$work/manual.out"
grep -q '^core: ' "$work/manual.out" || fail 'manual transport did not dispatch'

mkdir -p "$work/release"
"$root/src/bundle/pack.sh" \
	--snapshot "$work/snapshot" \
	--output "$work/release/ds-$platform.tar.gz" >/dev/null
install_root=$(
	DS_REPOSITORY=invalid/invalid "$root/src/install.sh" \
		--release-url "file://$work/release" \
		--platform "$platform" \
		--prefix "$work/install-release" \
		--no-apply
)
[ "$install_root" = "$work/install-release/versions/0.0.0-snapshot" ] || fail 'installer used the wrong version path'
"$install_root/ds" status core >"$work/install.out"
grep -q '^core: ' "$work/install.out" || fail 'release installer did not dispatch'
repeated_install_root=$(
	DS_REPOSITORY=invalid/invalid "$root/src/install.sh" \
		--release-url "file://$work/release" \
		--platform "$platform" \
		--prefix "$work/install-release" \
		--no-apply
)
[ "$repeated_install_root" = "$install_root" ] || fail 'reinstalling the same release was not idempotent'
printf '%s\n' '0000000000000000000000000000000000000000000000000000000000000000' \
	>"$work/release/ds-$platform.tar.gz.sha256"
if DS_REPOSITORY=invalid/invalid "$root/src/install.sh" \
	--release-url "file://$work/release" \
	--platform "$platform" \
	--prefix "$work/install-tampered" \
	--no-apply >/dev/null 2>&1; then
	fail 'installer accepted a mismatched release checksum'
fi

printf '%s\n' 'contract: ok'
