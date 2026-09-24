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
command -v taplo >/dev/null 2>&1 || die 'taplo is required'

taplo get -f "$root/src/catalog.toml" -o json layers >"$work/layers.json"
taplo get -f "$root/src/catalog.toml" -o json extends >"$work/extends.json"
jq -n --slurpfile definitions "$work/layers.json" --slurpfile parents "$work/extends.json" '
  ($definitions[0] | del(.optional)) as $layers |
  def expand($name; $seen):
    if ($seen | index($name)) then error("layer inheritance cycle") else
    ($parents[0][$name] // []) as $parents |
    (if $parents == ["*"] then ($layers | keys | map(select(. != $name))) else $parents end) as $bases |
    if $layers[$name] == null then error("unknown parent layer") else
    ([$bases[] | expand(.; $seen + [$name])[]] + [$name] | unique) end end;
  {layers: ($layers | with_entries(.value = [expand(.key; [])[] as $p | $layers[$p][]] | .value |= reduce .[] as $x ([]; if index($x) then . else . + [$x] end))),
   profiles: ($layers | with_entries(.value = [expand(.key; [])[] | select(. != "all")])),
   optional: ($definitions[0].optional // [])}
' >"$work/resolved.json"
printf '%s\n' '{}' >"$work/components.json"
jq -r '[.layers[][], .optional[]] | unique[]' "$work/resolved.json" >"$work/component-names"
while IFS= read -r component; do
	commands=$("$mise_command" toml get --file "$root/src/catalog.toml" "components.$component.commands")
	owner=$("$mise_command" toml get --file "$root/src/catalog.toml" "components.$component.owner")
	tool=$("$mise_command" toml get --file "$root/src/catalog.toml" "components.$component.tool" 2>/dev/null || true)
	case "$owner" in runtime | native | mise) ;; *) die "invalid owner for $component: $owner" ;; esac
	version=
	if [ "$owner" = mise ]; then
		version_key=$component
		case "$tool" in http-*) version_key="http:${tool#http-}" ;; esac
		for profile in "$root"/src/mise/mise*.toml; do
			version=$("$mise_command" toml get --file "$profile" "tools.$version_key.version" 2>/dev/null ||
				"$mise_command" toml get --file "$profile" "tools.$version_key" 2>/dev/null || true)
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
jq --slurpfile components "$work/components.json" '. + {components: $components[0]}' \
	"$work/resolved.json" >"$work/catalog.json"
jq -r '
  def keyword: ":" + .;
  def keywords: "[" + (map(keyword) | join(" ")) + "]";
  def strings: "[" + (map(@json) | join(" ")) + "]";
  "(def catalog\n  @{:layers\n  {" + ([.layers | to_entries[] | ":" + .key + " " + (.value | keywords)] | join("\n   ")) + "}" +
  "\n  :profiles {" + ([.profiles | to_entries[] | ":" + .key + " " + (.value | keywords)] | join(" ")) + "}" +
  "\n  :optional " + (.optional | keywords) +
  "\n  :components\n  {" +
  ([.components | to_entries | sort_by(.key)[] |
    ":" + .key + " {:commands " + (.value.commands | strings) +
    " :owner :" + .value.owner +
    (if .value.tool then " :tool " + (.value.tool | @json) else "" end) +
    (if .value.version then " :version " + (.value.version | @json) else "" end) + "}"] | join("\n   ")) +
  "}})"
' "$work/catalog.json" >"$work/layers.janet"

jq -r '
  "typeset -gA _ds_profiles=(",
  (.profiles | to_entries[] | "  " + .key + " \"" + (.value | join(",")) + "\""),
  ")"
' "$work/catalog.json" >"$work/profiles.zsh"
profiles=$root/src/dotfiles/profiles.zsh

case "$mode" in
--write)
	cp "$work/layers.janet" "$target"
	cp "$work/profiles.zsh" "$profiles"
	printf '%s\n' "$target"
	;;
--check)
	if ! cmp -s "$work/layers.janet" "$target" || ! cmp -s "$work/profiles.zsh" "$profiles"; then
		diff -u "$target" "$work/layers.janet" >&2 || true
		die 'generated layer catalog is stale; run mise run generate'
	fi
	printf '%s\n' 'generated catalog: current'
	;;
esac
