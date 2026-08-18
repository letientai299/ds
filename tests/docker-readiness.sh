#!/bin/sh

set -eu

: "${DF_HELLO_WORLD_IMAGE:?run through mise so DF_HELLO_WORLD_IMAGE is set}"
: "${DF_ALPINE_IMAGE:?run through mise so DF_ALPINE_IMAGE is set}"

work=$(mktemp -d "${TMPDIR:-/tmp}/df-docker.XXXXXX")
tag=df-docker-e2e:local
cleanup() {
	docker image rm "$tag" >/dev/null 2>&1 || true
	rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

docker info >/dev/null
docker compose version >/dev/null
docker buildx version >/dev/null
docker pull "$DF_HELLO_WORLD_IMAGE" >/dev/null
docker run --rm "$DF_HELLO_WORLD_IMAGE" >/dev/null

printf 'FROM %s\n%s\n' "$DF_ALPINE_IMAGE" 'CMD ["printf", "df-docker-ok\\n"]' >"$work/Dockerfile"
docker buildx build --load --tag "$tag" "$work" >/dev/null
docker run --rm "$tag" >/dev/null

printf '%s\n' 'services:' '  smoke:' "    image: $DF_HELLO_WORLD_IMAGE" >"$work/compose.yml"
docker compose --file "$work/compose.yml" config --quiet

printf '%s\n' 'docker: ok'
