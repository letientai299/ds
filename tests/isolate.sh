#!/bin/sh

# Sourced by tests. The login shell exports XDG, mise, and ZDOTDIR paths, and
# lib/mise.janet keeps any MISE_*_DIR it inherits, so overriding HOME alone
# still reaches the real mise state.

isolate_home() {
	# Docker keeps its context and CLI plugins there; E2E needs the real engine.
	export DOCKER_CONFIG="${DOCKER_CONFIG:-$HOME/.docker}"
	export HOME="$1"
	export XDG_CONFIG_HOME="$1/.config" XDG_DATA_HOME="$1/.local/share"
	export XDG_STATE_HOME="$1/.local/state" XDG_CACHE_HOME="$1/.cache"
	export MISE_DATA_DIR="$XDG_DATA_HOME/mise"
	export MISE_STATE_DIR="$XDG_STATE_HOME/mise" MISE_CACHE_DIR="$XDG_CACHE_HOME/mise"
	export MISE_SYSTEM_CONFIG_DIR="$1/.mise-system"
	# Trust stays: mise walks up from the checkout to trusted parents.
	unset MISE_CONFIG_DIR MISE_ENV MISE_GLOBAL_CONFIG_FILE MISE_GLOBAL_CONFIG_ROOT \
		MISE_OVERRIDE_CONFIG_FILENAMES MISE_CEILING_PATHS ZDOTDIR DS_MISE_ACTIVATE
	export GIT_CONFIG_GLOBAL=/dev/null
	export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
	export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid
	# The sandbox shares one Go cache across tests; -modcacherw keeps it removable.
	go_cache=${DS_TEST_GO_CACHE:-$1/.cache/go}
	export GOCACHE="$go_cache/build" GOMODCACHE="$go_cache/mod" GOFLAGS=-modcacherw
	mkdir -p "$1"
}
