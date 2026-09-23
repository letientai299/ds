# shellcheck shell=sh
# SHA-256 helper shared by the controller-side scripts.
#
# Not for src/bootstrap.sh, src/pull.sh or src/install.sh: those three run alone
# on a target or straight out of a curl pipe, so they keep their own copies and
# their own fail-open policies. Nothing here is ever copied into a snapshot.

if command -v sha256sum >/dev/null 2>&1; then
	checksum_kind=sha256sum
elif command -v shasum >/dev/null 2>&1; then
	checksum_kind=shasum
else
	die 'a SHA-256 utility is required'
fi

sha256_file() {
	case "$checksum_kind" in
	sha256sum) sha256sum "$1" | {
		read -r digest _rest
		printf '%s\n' "$digest"
	} ;;
	shasum) shasum -a 256 "$1" | {
		read -r digest _rest
		printf '%s\n' "$digest"
	} ;;
	esac
}
