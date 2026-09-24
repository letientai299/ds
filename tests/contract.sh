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
checkout_root=$(CDPATH='' cd -P "$work/checkout" && pwd)
[ "$checkout_dispatch" = "$checkout_root/src/scripts/main.janet" ] || fail 'checkout launcher did not use the dist runtime fallback'

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
grep -q '^  packages .*neovim' "$work/apply.out" || fail 'Neovim is missing from core'
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
if grep -q '^  packages .*docker\|^  converge Docker' "$work/skip.out"; then
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

mkdir -p "$work/selected-home/config/ds"
printf '%s\n' starship >"$work/selected-home/config/ds/components"
HOME=$work/selected-home \
	XDG_CONFIG_HOME=$work/selected-home/config \
	XDG_STATE_HOME=$work/selected-home/state \
	DS_ROOT=$root DS_JANET=$janet DS_MISE=$mise \
	"$root/ds" apply core --dry-run >"$work/selected.out"
grep -q '^  packages .*starship' "$work/selected.out" || fail 'preview omitted selected Starship'
[ "$(cat "$work/selected-home/config/ds/components")" = starship ] || fail 'preview changed selections'
[ ! -e "$work/selected-home/.local" ] || fail 'preview wrote managed links'

for spelling in help --help -h; do
	DS_ROOT=$root DS_JANET=$janet DS_MISE=$mise "$root/ds" "$spelling" \
		>"$work/help.out" 2>"$work/help.err" || fail "ds $spelling exited non-zero"
	grep -q '^usage: ds ' "$work/help.out" || fail "ds $spelling printed no usage to stdout"
	grep -q '^layers: core, remote$' "$work/help.out" || fail "ds $spelling omits the catalog layers"
	[ ! -s "$work/help.err" ] || fail "ds $spelling wrote to stderr"
done

# Every rejected form must fail before touching the home it was pointed at.
reject() {
	description=$1
	shift
	HOME=$work/reject-home \
		XDG_CONFIG_HOME=$work/reject-home/config \
		XDG_STATE_HOME=$work/reject-home/state \
		DS_ROOT=$root DS_JANET=$janet DS_MISE=$mise \
		"$root/ds" "$@" >"$work/reject.out" 2>"$work/reject.err" &&
		fail "$description was accepted"
	grep -q '^ds: ' "$work/reject.err" || fail "$description lacks a ds: diagnostic"
	[ ! -e "$work/reject-home" ] || fail "$description wrote to the isolated home"
}
reject 'unapply with an unknown layer' unapply cor
reject 'status with an unknown layer' status cor
reject 'diff with an unknown layer' diff cor
reject 'apply with an unknown layer' apply cor
reject 'apply with an unskippable component' apply core --skip fzf
reject 'adopt with --skip' adopt core --skip docker
reject 'force with --skip' force core --skip docker
reject 'add with a misspelled flag' add starship --dryrun
reject 'add with a trailing argument' add starship extra
reject 'an unknown command' bogus-command

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
sh "$root/tests/aliases.sh" "$snapshot_root/src/dotfiles/shell.zsh"
[ -f "$snapshot_root/src/dotfiles/omz/LICENSE.txt" ] || fail 'snapshot is missing OMZ license'
[ -f "$snapshot_root/src/THIRD-PARTY.md" ] || fail 'snapshot is missing third-party notices'
grep -q '	src/THIRD-PARTY.md$' "$work/snapshot/manifest.tsv" ||
	fail 'third-party notices are not covered by the manifest'
[ ! -L "$work/snapshot-install/current" ] || fail 'bootstrap activated a staged version'
"$snapshot_root/ds" activate 0.0.0-snapshot --prefix "$work/snapshot-install" >/dev/null
[ "$(readlink "$work/snapshot-install/current")" = versions/0.0.0-snapshot ] ||
	fail 'current does not name the installed version relatively'
[ -x "$work/snapshot-install/current/ds" ] || fail 'current does not resolve to a usable install'
sh "$root/tests/plugins.sh" "$work/snapshot-install/current/src/dotfiles/shell.zsh"

pull_root=$(
	"$root/src/pull.sh" \
		--url "file://$work/snapshot" \
		--prefix "$work/pull-install" \
		--manifest-sha256 "$snapshot_sha"
)
"$pull_root/ds" status core >"$work/pull.out"
grep -q '^core: ' "$work/pull.out" || fail 'pull transport did not dispatch'

[ -z "$(find "$work/pull-install/incoming" -mindepth 1 -maxdepth 1 2>/dev/null)" ] ||
	fail 'pull left its staging directory behind'

cp -R "$work/snapshot" "$work/corrupt-snapshot"
printf '%s\n' 'corrupted' >>"$work/corrupt-snapshot/files/src/dotfiles/gitignore"
if "$root/src/pull.sh" \
	--url "file://$work/corrupt-snapshot" \
	--prefix "$work/corrupt-pull-install" \
	--manifest-sha256 "$snapshot_sha" >"$work/corrupt-pull.out" 2>"$work/corrupt-pull.err"; then
	fail 'pull accepted a corrupted payload'
fi
grep -q 'checksum mismatch: src/dotfiles/gitignore' "$work/corrupt-pull.err" ||
	fail 'pull did not name the corrupted payload'
[ -z "$(find "$work/corrupt-pull-install/incoming" -mindepth 1 -maxdepth 1 2>/dev/null)" ] ||
	fail 'failed pull left its staging directory behind'

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
cp "$root/tests/fake-ssh.sh" "$work/fake-ssh"
chmod 0755 "$work/fake-ssh"
mkdir -p "$work/ssh temp"
push_root=$(
	TMPDIR="$work/ssh temp" DS_SSH=$work/fake-ssh "$root/src/bundle/push.sh" \
		--snapshot "$work/snapshot" \
		--host fixture
)
"$push_root/ds" status core >"$work/push.out"
grep -q '^core: ' "$work/push.out" || fail 'SSH push transport did not dispatch'

# push.sh interpolates manifest paths into a remote command string, so the
# fixture has to be internally consistent enough to reach that interpolation.
inject_path='a";touch pwned;"b'
mkdir -p "$work/inject/files"
printf '%s\n' 'payload' >"$work/inject/files/$inject_path"
inject_file_sha=$(shasum -a 256 "$work/inject/files/$inject_path" | awk '{print $1}')
printf 'ds-bundle-v1%s0.0.0-inject\nfile%s0644%s%s%s%s\n' \
	"$tab" "$tab" "$tab" "$inject_file_sha" "$tab" "$inject_path" >"$work/inject/manifest.tsv"
shasum -a 256 "$work/inject/manifest.tsv" | awk '{print $1}' >"$work/inject/manifest.sha256"
if DS_SSH=$work/fake-ssh "$root/src/bundle/push.sh" \
	--snapshot "$work/inject" \
	--host fixture >"$work/inject.out" 2>"$work/inject.err"; then
	fail 'push accepted a manifest path with shell metacharacters'
fi
grep -q 'unsafe bundle path' "$work/inject.err" ||
	fail 'push rejected the injected snapshot for the wrong reason'
[ ! -e "$work/remote-home/pwned" ] || fail 'push executed an injected remote command'
[ ! -e "$root/pwned" ] || fail 'push executed an injected command in the checkout'

"$root/src/bundle/pack.sh" --snapshot "$work/snapshot" --output "$work/manual-1.tar.gz" >/dev/null
"$root/src/bundle/pack.sh" --snapshot "$work/snapshot" --output "$work/manual-2.tar.gz" >/dev/null
[ "$(shasum -a 256 "$work/manual-1.tar.gz" | awk '{print $1}')" = \
	"$(shasum -a 256 "$work/manual-2.tar.gz" | awk '{print $1}')" ] || fail 'manual bundle is not reproducible'
TZ=Asia/Tokyo "$root/src/bundle/pack.sh" --snapshot "$work/snapshot" --output "$work/manual-tz.tar.gz" >/dev/null
[ "$(shasum -a 256 "$work/manual-1.tar.gz" | awk '{print $1}')" = \
	"$(shasum -a 256 "$work/manual-tz.tar.gz" | awk '{print $1}')" ] || fail 'bundle digest depends on the builder timezone'
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
