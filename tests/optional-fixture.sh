#!/bin/sh

optional_fixture() {
	mkdir -p "$2"
	cp "$1/ds" "$2/ds"
	cp -R "$1/src" "$1/tests" "$2/"
	cat >>"$2/src/scripts/generated/layers.janet" <<'JANET'
(def catalog (merge catalog {:optional [:example]
  :components (merge (get catalog :components)
    {:example {:commands ["example"] :owner :mise :version "1.23.0"}})}))
JANET
	printf '%s\n' '[tools]' 'example = "1.23.0"' >"$2/src/mise/mise.example.toml"
}
