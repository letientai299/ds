#!/bin/sh

set -eu

die() {
	printf '%s\n' "ds push: $*" >&2
	exit 1
}

usage() {
	printf '%s\n' 'usage: src/bundle/push.sh --snapshot DIR --host HOST [--prefix RELATIVE_PATH]'
}

root=$(dirname -- "$0")/../..
root=$(CDPATH='' cd "$root" && pwd)
snapshot=
host=
prefix=.local/share/ds
ssh_command=${DS_SSH:-ssh}

while [ "$#" -gt 0 ]; do
	case "$1" in
	--snapshot | --host | --prefix)
		[ "$#" -ge 2 ] || die "$1 requires a value"
		case "$1" in
		--snapshot) snapshot=$2 ;;
		--host) host=$2 ;;
		--prefix) prefix=$2 ;;
		esac
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown argument: $1" ;;
	esac
done

[ -n "$snapshot" ] || die '--snapshot is required'
[ -d "$snapshot" ] || die "snapshot is missing: $snapshot"
snapshot=$(CDPATH='' cd "$snapshot" && pwd)
[ -n "$host" ] || die '--host is required'
case "$host" in -*) die 'host must not begin with a hyphen' ;; esac
case "$prefix" in
'' | /* | ../* | */../* | */.. | *[!0-9A-Za-z._/-]*) die 'prefix must be a safe relative path' ;;
esac
command -v "$ssh_command" >/dev/null 2>&1 || die "SSH command is missing: $ssh_command"

# A snapshot carries a few hundred payload files and each one used to cost its
# own handshake, so every push multiplexes them over a single master connection.
control_dir=$(mktemp -d "${TMPDIR:-/tmp}/ds-push.XXXXXX")
ssh_run() {
	"$ssh_command" -o ControlMaster=auto -o ControlPersist=60 \
		-o "ControlPath=\"$control_dir/%C\"" "$@"
}

shutdown_master() {
	ssh_run -O exit "$host" >/dev/null 2>&1 || true
	rm -rf "$control_dir"
}
trap shutdown_master EXIT
trap 'exit 143' HUP INT TERM

remote() {
	ssh_run "$host" "$1"
}

manifest_sha=$(sed -n '1p' "$snapshot/manifest.sha256")
version=$(
	"$root/src/bootstrap.sh" \
		--source "$snapshot" \
		--manifest-sha256 "$manifest_sha" \
		--verify-only
)
remote_prefix=\$HOME/$prefix
remote_source=$remote_prefix/incoming/$version
remote_install=$remote_prefix/versions/$version

transfer_list=$control_dir/files
printf '%s\n' manifest.tsv >"$transfer_list"
tab=$(printf '\t')
while IFS="$tab" read -r record mode _expected_sha256 path _extra; do
	[ "$record" = file ] || continue
	case "$mode" in 0644 | 0755) ;; *) die "invalid mode for $path" ;; esac
	case "$path" in
	'' | /* | ../* | */../* | */.. | *[!0-9A-Za-z._/-]*) die "unsafe bundle path: $path" ;;
	esac
	printf 'files/%s\n' "$path" >>"$transfer_list"
done <"$snapshot/manifest.tsv"

if remote "test -x \"$remote_install/ds\"" >/dev/null 2>&1; then
	remote "printf '%s\\n' \"$remote_install\""
	exit 0
fi

printf '%s\n' "ds push: transferring $version" >&2
if command -v tar >/dev/null 2>&1 && remote 'command -v tar' >/dev/null 2>&1; then
	# Stream only verified files; dereference source links.
	tar -chf - -C "$snapshot" -T "$transfer_list" |
		remote "mkdir -p \"$remote_source\" && tar -xf - -C \"$remote_source\""
else
	remote "mkdir -p \"$remote_source\" && cat >\"$remote_source/manifest.tsv\" && chmod 0644 \"$remote_source/manifest.tsv\"" \
		<"$snapshot/manifest.tsv"
	while IFS="$tab" read -r record mode _expected_sha256 path _extra; do
		[ "$record" = file ] || continue
		remote_file=$remote_source/files/$path
		remote_dir=${remote_file%/*}
		remote "mkdir -p \"$remote_dir\" && cat >\"$remote_file\" && chmod \"$mode\" \"$remote_file\"" \
			<"$snapshot/files/$path"
	done <"$snapshot/manifest.tsv"
fi

printf '%s\n' "ds push: verifying $version" >&2
remote "sh \"$remote_source/files/src/bootstrap.sh\" --source \"$remote_source\" --prefix \"$remote_prefix\" --manifest-sha256 \"$manifest_sha\""
