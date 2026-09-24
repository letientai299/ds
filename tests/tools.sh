#!/bin/sh
set -eu

root=$(CDPATH='' cd "$(dirname -- "$0")/.." && pwd)
tools=${1:-$root/src/tools}
work=$(mktemp -d "${TMPDIR:-/tmp}/ds-tools.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP INT TERM
mkdir -p "$work/bin" "$work/source space" "$work/capture"
export DS_TEST_CAPTURE="$work/capture"
cat >"$work/bin/docker" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >>"$DS_TEST_CAPTURE/args"
if [ "$1" = run ]; then
  for arg do
    case "$arg" in
    *:/usr/share/caddy:ro)
      site=${arg%:/usr/share/caddy:ro}
      cp -R "$site/." "$DS_TEST_CAPTURE/site"
      ;;
    *:/livereload:ro)
      cp -R "${arg%:/livereload:ro}/." "$DS_TEST_CAPTURE/reload"
      ;;
    esac
  done
  exit 42
fi
SH
chmod +x "$work/bin/docker"
export PATH="$work/bin:$PATH"

"$tools/serve" --help >"$work/help"
grep -q -- --no-live "$work/help"
for port in '' abc 0 65536 999999999999999999999; do
	if "$tools/serve" --port "$port" >"$work/out" 2>&1; then
		echo 'serve accepted invalid port' >&2
		exit 1
	fi
done
for argument in --port --unknown; do
	if "$tools/serve" "$argument" >"$work/out" 2>&1; then
		echo 'serve accepted invalid argument' >&2
		exit 1
	fi
done
[ ! -e "$work/capture/args" ]

html="$work/source space/line
break.html"
printf '%s\n' '<html><body>original</body></html>' >"$html"
printf '%s\n' hidden >"$work/source space/.hidden"
cp "$html" "$work/original"
"$tools/serve" --no-open -p 8765 "$work/source space" >"$work/out" 2>&1 && code=0 || code=$?
[ "$code" -eq 42 ]
grep -qx '8765:80' "$work/capture/args"
grep -qx stop "$work/capture/args"
grep -q '/_livereload.js' "$work/capture/site/line
break.html"
[ "$(cat "$work/capture/reload/_livereload/token")" = 1 ]
[ "$(cat "$work/capture/site/.hidden")" = hidden ]
cmp "$html" "$work/original"

rm -rf "$work/capture/site" "$work/capture/reload" "$work/capture/args"
"$tools/serve" --no-open --no-live "$work/source space" >"$work/out" 2>&1 && code=0 || code=$?
[ "$code" -eq 42 ]
cmp "$work/capture/site/line
break.html" "$work/original"
[ ! -e "$work/capture/reload" ]

printf '%s\n' 'tools: ok'
