#!/bin/sh

set -eu

die() {
	printf '%s\n' "ds setup: $*" >&2
	exit 1
}

usage() {
	cat <<'USAGE'
usage: scripts/install.sh [--no-apply] [--layer LAYER] [--prefix DIR]
                         [--skip docker] [--shell] [--yes] [--force]

Uses the current checkout, including from subdirectories.
Otherwise clones main under ~/.local/share/ds-source.
DS_SOURCE_REF selects another ds branch when cloning.
Installs prerequisites and reapplies selected layers; initially core.
Existing installations prompt before updating source checkouts.
--yes accepts updates without prompting.
Repeat --layer to apply several layers together.
--force backs up conflicting configuration before applying.
--no-apply prepares runtimes and previews changes.
--prefix sets the clone directory outside a checkout.
--shell opens Zsh after applying.
USAGE
}

prefix=${XDG_DATA_HOME:-$HOME/.local/share}/ds-source
prefix_set=false
layers=
update=false
yes=false
resumed=${DS_INSTALL_UPDATED_ROOT:-}
unset DS_INSTALL_UPDATED_ROOT
force=false
apply=true
shell=false
skip=
while [ "$#" -gt 0 ]; do
	case "$1" in
	--prefix | --layer | --skip)
		[ "$#" -ge 2 ] && [ -n "$2" ] || die "$1 requires a value"
		case "$1" in
		--prefix)
			prefix=$2
			prefix_set=true
			;;
		--layer)
			case "$2" in core | remote | extra | ui | all) ;; *) die "unknown layer: $2" ;; esac
			layers="${layers:+$layers }$2"
			;;
		--skip) skip=$2 ;;
		esac
		shift 2
		;;
	--yes)
		yes=true
		shift
		;;
	--force)
		force=true
		shift
		;;
	--no-apply)
		apply=false
		shift
		;;
	--shell)
		shell=true
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown argument: $1" ;;
	esac
done
if [ -z "$layers" ]; then
	selection=${XDG_CONFIG_HOME:-$HOME/.config}/ds/layer
	if [ -f "$selection" ]; then
		saved=$(cat "$selection")
		case "$saved" in '' | ,* | *, | *,,* | *[!a-z,]*) die 'invalid saved layers' ;; esac
		layers=$(printf '%s' "$saved" | tr ',' ' ')
		for layer in $layers; do
			case "$layer" in core | remote | extra | ui | all) ;; *) die "unknown saved layer: $layer" ;; esac
		done
	fi
fi
layers=${layers:-core}
case "$skip" in '' | docker) ;; *) die "unsupported skip: $skip" ;; esac
[ "$apply:$shell" != false:true ] || die '--shell requires applying'

operating_system=$(uname -s)
case "$operating_system:$(uname -m)" in
Darwin:arm64) platform=macos-arm64 ;;
Darwin:x86_64) platform=macos-x64 ;;
Linux:aarch64 | Linux:arm64) platform=linux-arm64-musl ;;
Linux:x86_64 | Linux:amd64) platform=linux-x64-musl ;;
*) die 'unsupported operating system or architecture' ;;
esac

root=${resumed:-$(pwd -P)}
while :; do
	if [ -f "$root/ds" ] && [ -f "$root/.config/mise/config.toml" ] &&
		[ -f "$root/src/runtime/fetch.sh" ] && [ -f "$root/src/runtime/build.sh" ]; then
		break
	fi
	if [ "$root" = / ]; then
		root=
		break
	fi
	root=$(dirname -- "$root")
done

if [ -z "$root" ] && [ "$prefix_set" = false ] && [ -L "$HOME/.local/bin/ds" ]; then
	launcher=$HOME/.local/bin/ds
	while [ -L "$launcher" ]; do
		directory=$(CDPATH='' cd -P "$(dirname -- "$launcher")" && pwd)
		launcher=$(readlink "$launcher")
		case "$launcher" in /*) ;; *) launcher=$directory/$launcher ;; esac
	done
	directory=$(dirname -- "$launcher")
	if [ -f "$directory/scripts/install.sh" ]; then
		root=$(CDPATH='' cd "$directory" && pwd -P)
		prefix=$(dirname -- "$root")
	fi
fi

if [ -z "$root" ]; then
	case "$prefix" in /*) ;; *) prefix=$PWD/$prefix ;; esac
	if [ -d "$prefix/ds" ]; then
		root=$(CDPATH='' cd "$prefix/ds" && pwd -P)
	fi
fi
if [ -n "$root" ] && [ "$resumed" != "$root" ]; then
	if [ "$yes" = false ]; then
		[ -t 0 ] || die 'existing installation requires confirmation; use --yes'
		printf 'Update existing installation at %s? [y/N] ' "$root" >&2
		IFS= read -r answer || exit 1
		case "$answer" in y | Y | yes | YES) ;; *) exit 0 ;; esac
	fi
	update=true
fi

privileged() {
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
	elif command -v sudo >/dev/null 2>&1; then
		sudo "$@"
	else
		die 'missing prerequisites require root or sudo'
	fi
}

prerequisites() {
	if [ "$operating_system" = Darwin ]; then
		xcrun --find clang >/dev/null 2>&1 || die 'install Command Line Tools: xcode-select --install'
		if [ "$apply" = true ]; then
			command -v brew >/dev/null 2>&1 || die 'Homebrew is required to apply on macOS'
		fi
		if ! command -v xz >/dev/null 2>&1; then
			command -v brew >/dev/null 2>&1 || die 'install xz with Homebrew'
			brew install xz
		fi
		return
	fi
	if command -v apt-get >/dev/null 2>&1; then
		packages=
		for entry in git:git curl:curl xz:xz-utils gcc:build-essential; do
			command -v "${entry%%:*}" >/dev/null 2>&1 || packages="$packages ${entry#*:}"
		done
		if [ -n "$packages" ] || [ ! -s /etc/ssl/certs/ca-certificates.crt ]; then
			privileged apt-get update
			# Package names are fixed above.
			# shellcheck disable=SC2086
			privileged apt-get install -y --no-install-recommends ca-certificates $packages
		fi
	elif command -v apk >/dev/null 2>&1; then
		privileged apk add --no-cache build-base ca-certificates curl git xz
	elif command -v dnf >/dev/null 2>&1; then
		privileged dnf install -y ca-certificates curl git xz gcc make
	else
		die 'source setup requires apt-get, apk, dnf, or macOS'
	fi
}

prerequisites
for command in git curl tar xz; do
	command -v "$command" >/dev/null 2>&1 || die "missing prerequisite: $command"
done

stage=
temporary=
cleanup() {
	[ -z "$stage" ] || rm -rf "$stage"
	[ -z "$temporary" ] || rm -f "$temporary"
}
trap cleanup EXIT
trap 'exit 143' HUP INT TERM

clone() {
	repository=$1
	destination=$2
	ref=main
	[ "$repository" != ds ] || ref=${DS_SOURCE_REF:-main}
	if [ -e "$destination" ] || [ -L "$destination" ]; then
		[ -d "$destination/.git" ] || [ -f "$destination/.git" ] || die "not a checkout: $destination"
		return
	fi
	mkdir -p "$(dirname -- "$destination")"
	stage=$(mktemp -d "$destination.clone.XXXXXX")
	git clone --depth 1 --branch "$ref" "https://github.com/letientai299/$repository.git" "$stage"
	[ ! -e "$destination" ] || die "checkout appeared during clone: $destination"
	mv "$stage" "$destination"
	stage=
}

if [ -z "$root" ]; then
	case "$prefix" in /*) ;; *) prefix=$PWD/$prefix ;; esac
	clone ds "$prefix/ds"
	root=$(CDPATH='' cd "$prefix/ds" && pwd -P)
fi
[ -f "$root/.config/mise/config.toml" ] || die "missing project configuration: $root"
printf '%s\n' "ds setup: checkout $root" >&2

if [ "$update" = true ]; then
	DS_UPDATE_SOURCE_ONLY=true sh "$root/src/scripts/update.sh"
	set --
	for layer in $layers; do
		set -- "$@" --layer "$layer"
	done
	[ "$apply" = true ] || set -- "$@" --no-apply
	[ "$force" = false ] || set -- "$@" --force
	[ "$shell" = false ] || set -- "$@" --shell
	[ -z "$skip" ] || set -- "$@" --skip "$skip"
	DS_INSTALL_UPDATED_ROOT=$root exec sh "$root/scripts/install.sh" --prefix "$prefix" "$@"
fi

sources=
for layer in $layers; do
	case "$layer" in
	core) required=nvim ;;
	remote) required="nvim tmux" ;;
	ui) required=kitty ;;
	all) required="nvim tmux kitty" ;;
	extra) required= ;;
	esac
	for name in $required; do
		case " $sources " in *" $name "*) ;; *) sources="${sources:+$sources }$name" ;; esac
	done
done
for name in $sources; do
	case "$name" in
	nvim) configured=${DS_NVIM_SOURCE:-} ;;
	tmux) configured=${DS_TMUX_SOURCE:-} ;;
	kitty) configured=${DS_KITTY_SOURCE:-} ;;
	esac
	if [ -n "$configured" ]; then
		[ -d "$configured" ] || die "missing configuration: $configured"
		configured=$(CDPATH='' cd "$configured" && pwd -P)
	else
		configured=$root/../$name.conf
		clone "$name.conf" "$configured"
		configured=$(CDPATH='' cd "$configured" && pwd -P)
	fi
	case "$name" in
	kitty)
		DS_KITTY_SOURCE=$configured
		export DS_KITTY_SOURCE
		CGO_ENABLED=0 mise exec go@1.27.1 -- go -C "$configured" build -trimpath -o bin/kt ./cmd/kt
		;;
	nvim)
		DS_NVIM_SOURCE=$configured
		export DS_NVIM_SOURCE
		;;
	tmux)
		DS_TMUX_SOURCE=$configured
		export DS_TMUX_SOURCE
		;;
	esac
done

setting() {
	value=$(sed -n "s/^$1 = \"\([0-9a-f.]*\)\"$/\1/p" "$root/.config/mise/config.toml")
	[ -n "$value" ] || die "missing runtime setting: $1"
	printf '%s\n' "$value"
}

DS_RUNTIME_DIST=$root/dist/runtime
DS_JANET_VERSION=$(setting DS_JANET_VERSION)
DS_JANET_SOURCE_SHA256=$(setting DS_JANET_SOURCE_SHA256)
DS_JANET_HEADER_SHA256=$(setting DS_JANET_HEADER_SHA256)
DS_JANET_SHELL_SHA256=$(setting DS_JANET_SHELL_SHA256)
export DS_RUNTIME_DIST DS_JANET_VERSION DS_JANET_SOURCE_SHA256
export DS_JANET_HEADER_SHA256 DS_JANET_SHELL_SHA256

sh "$root/src/runtime/fetch-mise.sh" "$platform"
DS_MISE=$DS_RUNTIME_DIST/bin/$platform/mise
DS_JANET=$DS_RUNTIME_DIST/bin/$platform/janet
export DS_MISE DS_JANET
runtime_version=
if [ -x "$DS_JANET" ]; then
	runtime_version=$("$DS_JANET" -v 2>/dev/null) || runtime_version=
fi
if [ "${runtime_version%%-*}" != "$DS_JANET_VERSION" ]; then
	janet_source=$(sh "$root/src/runtime/fetch.sh")
	if [ "$operating_system" = Darwin ]; then
		sh "$root/src/runtime/build.sh" "$platform"
	else
		compiler=musl-gcc
		if command -v "$compiler" >/dev/null 2>&1; then
			set -- -static
		else
			compiler=cc
			set --
		fi
		temporary=$(mktemp "$DS_JANET.part.XXXXXX")
		"$compiler" -std=c99 -O2 -DNDEBUG -DJANET_NO_DYNAMIC_MODULES \
			-I"$janet_source" "$janet_source/janet.c" "$janet_source/shell.c" \
			"$@" -pthread -ldl -lm -o "$temporary"
		chmod 0755 "$temporary"
		mv "$temporary" "$DS_JANET"
		temporary=
	fi
fi

set -- apply
for layer in $layers; do
	set -- "$@" "$layer"
done
[ "$force" = false ] || set -- "$@" --force
[ -z "$skip" ] || set -- "$@" --skip "$skip"
if [ "$apply" = false ]; then
	for layer in $layers; do
		"$root/ds" diff "$layer"
	done
	set -- "$@" --dry-run
fi
"$root/ds" "$@"
completion_dir=$HOME/.local/share/zsh/site-functions
mkdir -p "$completion_dir"
temporary=$(mktemp "$completion_dir/_ds.XXXXXX")
"$root/ds" completion zsh >"$temporary"
printf '%s\n' '_ds_complete "$@"' >>"$temporary"
chmod 0644 "$temporary"
mv "$temporary" "$completion_dir/_ds"
temporary=
printf '%s\n' "ds setup: launcher $root/ds"
if [ "$shell" = true ]; then
	exec zsh -l
fi
