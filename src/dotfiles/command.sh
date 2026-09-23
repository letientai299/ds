# shellcheck shell=bash

ds() {
	local executable=${DS_DS:-$HOME/.local/bin/ds}
	command "$executable" "$@"
	local exit_status=$?
	case " $* " in
	*" --dry-run "* | *" --help "* | *" -h "*) return "$exit_status" ;;
	esac
	case "${1:-}:$exit_status" in
	apply:0 | add:0 | adopt:0 | force:0 | unapply:0 | activate:0 | rollback:0)
		if [ -x "$executable" ]; then
			eval "$(command "$executable" shell-init)"
		fi
		;;
	esac
	return "$exit_status"
}
