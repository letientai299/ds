#!/bin/sh

set -eu

: "${DS_HELLO_WORLD_IMAGE:?run through mise so DS_HELLO_WORLD_IMAGE is set}"
: "${DS_ALPINE_IMAGE:?run through mise so DS_ALPINE_IMAGE is set}"

work=$(mktemp -d "${TMPDIR:-/tmp}/ds-docker.XXXXXX")
tag=ds-docker-e2e:local
cleanup() {
	docker image rm "$tag" >/dev/null 2>&1 || true
	rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

docker info >/dev/null
docker compose version >/dev/null
docker buildx version >/dev/null
docker pull "$DS_HELLO_WORLD_IMAGE" >/dev/null
docker run --rm "$DS_HELLO_WORLD_IMAGE" >/dev/null

printf 'FROM %s\n%s\n' "$DS_ALPINE_IMAGE" 'CMD ["printf", "ds-docker-ok\\n"]' >"$work/Dockerfile"
docker buildx build --load --tag "$tag" "$work" >/dev/null
docker run --rm "$tag" >/dev/null

printf '%s\n' 'services:' '  smoke:' "    image: $DS_HELLO_WORLD_IMAGE" >"$work/compose.yml"
docker compose --file "$work/compose.yml" config --quiet

printf '%s\n' 'docker: ok'
