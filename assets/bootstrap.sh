#!/bin/sh
# Install the latest ds main build, then add the given selectors (default:
# -l core). Requires curl or wget and a SHA-256 tool.
#
#   sh -c "$(curl -fsSL https://letientai.io/ds/bootstrap.sh)" -- -l core -l extra
set -eu

base=${DS_DOWNLOAD_URL:-https://letientai.io/ds}

die() {
	printf 'ds bootstrap: %s\n' "$*" >&2
	exit 1
}

case "$(uname -s)" in
Darwin) os=darwin ;;
Linux) os=linux ;;
*) die "unsupported operating system: $(uname -s)" ;;
esac
case "$(uname -m)" in
arm64 | aarch64) arch=arm64 ;;
x86_64 | amd64) arch=amd64 ;;
*) die "unsupported architecture: $(uname -m)" ;;
esac

fetch() {
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL -H 'Cache-Control: no-cache' -o "$2" "$1"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$2" "$1"
	else
		die 'curl or wget is required'
	fi
}

sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d ' ' -f 1
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | cut -d ' ' -f 1
	elif command -v openssl >/dev/null 2>&1; then
		openssl dgst -sha256 -r "$1" | cut -d ' ' -f 1
	else
		die 'sha256sum, shasum, or openssl is required'
	fi
}

work=$(mktemp -d "${TMPDIR:-/tmp}/ds-bootstrap.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 130' HUP INT TERM

# The site can publish between the manifest and binary requests; refetch
# the manifest and never run an unverified binary.
attempt=1
while :; do
	fetch "$base/latest.tsv" "$work/latest.tsv" || die "cannot download $base/latest.tsv"
	line=$(awk -F '\t' -v p="$os/$arch" '$1 == p { print $2 " " $3 }' "$work/latest.tsv")
	[ -n "$line" ] || die "no build for $os/$arch"
	name=${line% *}
	want=${line#* }
	if fetch "$base/$name" "$work/ds" && [ "$(sha256 "$work/ds")" = "$want" ]; then
		break
	fi
	[ "$attempt" -lt 3 ] || die "$name did not verify after $attempt attempts"
	attempt=$((attempt + 1))
	sleep "$attempt"
done
chmod 755 "$work/ds"
printf 'ds bootstrap: %s verified\n' "$name" >&2

[ "$#" -gt 0 ] || set -- -l core
"$work/ds" add "$@"
