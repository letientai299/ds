#!/bin/sh

set -eu

die() {
	printf '%s\n' "generate: $*" >&2
	exit 1
}

root=$(dirname -- "$0")/../..
root=$(CDPATH='' cd "$root" && pwd)
mode=${1:---check}
mise_command=${DS_MISE:-mise}
target=$root/src/scripts/generated/layers.janet
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-generate.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

case "$mode" in --check | --write) ;; *) die 'usage: src/scripts/generate.sh [--check|--write]' ;; esac
command -v "$mise_command" >/dev/null 2>&1 || die 'mise is required'
command -v jq >/dev/null 2>&1 || die 'jq is required'

core=$("$mise_command" toml get --file "$root/src/catalog.toml" layers.core)
remote=$("$mise_command" toml get --file "$root/src/catalog.toml" layers.remote)
optional=$("$mise_command" toml get --file "$root/src/catalog.toml" layers.optional)
printf '%s\n' '{}' >"$work/components.json"
printf '%s\n%s\n%s\n' "$core" "$remote" "$optional" |
	jq -r -s 'add | unique[]' >"$work/component-names"
while IFS= read -r component; do
	commands=$("$mise_command" toml get --file "$root/src/catalog.toml" "components.$component.commands")
	owner=$("$mise_command" toml get --file "$root/src/catalog.toml" "components.$component.owner")
	tool=$("$mise_command" toml get --file "$root/src/catalog.toml" "components.$component.tool" 2>/dev/null || true)
	case "$owner" in runtime | native | mise) ;; *) die "invalid owner for $component: $owner" ;; esac
	version=
	if [ "$owner" = mise ]; then
		version_key=$component
		[ "$tool" != http-delta ] || version_key=http:delta.version
		for profile in "$root"/src/mise/mise*.toml; do
			version=$("$mise_command" toml get --file "$profile" "tools.$version_key" 2>/dev/null || true)
			[ -z "$version" ] || break
		done
		[ -n "$version" ] || die "missing pinned version for $component"
	fi
	jq --arg component "$component" --arg owner "$owner" --arg tool "$tool" --argjson commands "$commands" --arg version "$version" \
		'. + {($component): ({commands: $commands, owner: $owner}
         + (if $tool == "" then {} else {tool: $tool} end)
         + (if $owner == "mise" then {version: $version} else {} end))}' \
		"$work/components.json" >"$work/components.next"
	mv "$work/components.next" "$work/components.json"
done <"$work/component-names"
jq -n \
	--argjson core "$core" \
	--argjson remote "$remote" \
	--argjson optional "$optional" \
	--slurpfile components "$work/components.json" \
	'{layers: {core: $core, remote: $remote, optional: $optional}, components: $components[0]}' \
	>"$work/catalog.json"
jq -r '
  def keyword: ":" + .;
  def keywords: "[" + (map(keyword) | join(" ")) + "]";
  def strings: "[" + (map(@json) | join(" ")) + "]";
  "(def catalog\n  @{:layers\n  {:core " + (.layers.core | keywords) +
  "\n   :remote " + (.layers.remote | keywords) + "}" +
  "\n  :optional " + (.layers.optional | keywords) +
  "\n  :components\n  {" +
  ([.components | to_entries | sort_by(.key)[] |
    ":" + .key + " {:commands " + (.value.commands | strings) +
    " :owner :" + .value.owner +
    (if .value.tool then " :tool " + (.value.tool | @json) else "" end) +
    (if .value.version then " :version " + (.value.version | @json) else "" end) + "}"] | join("\n   ")) +
  "}})"
' "$work/catalog.json" >"$work/layers.janet"

case "$mode" in
--write)
	cp "$work/layers.janet" "$target"
	printf '%s\n' "$target"
	;;
--check)
	if ! cmp -s "$work/layers.janet" "$target"; then
		diff -u "$target" "$work/layers.janet" >&2 || true
		die 'generated layer catalog is stale; run mise run generate'
	fi
	printf '%s\n' 'generated catalog: current'
	;;
esac
