# Throwaway test sandbox. tests/sandbox.sh builds and runs it.
ARG DS_UBUNTU_IMAGE
FROM ${DS_UBUNTU_IMAGE} AS base

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
    bash ca-certificates curl file git jq perl procps wget xz-utils zsh && \
    rm -rf /var/lib/apt/lists/*

FROM base AS janet

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends gcc libc6-dev && \
    rm -rf /var/lib/apt/lists/*
ARG DS_JANET_VERSION
ARG DS_JANET_SOURCE_SHA256
ARG DS_JANET_HEADER_SHA256
ARG DS_JANET_SHELL_SHA256
WORKDIR /src
RUN base=https://github.com/janet-lang/janet/releases/download/v$DS_JANET_VERSION && \
    curl -fsSL --retry 3 -O "$base/janet.c" -O "$base/janet.h" -O "$base/shell.c" && \
    printf '%s  %s\n' "$DS_JANET_SOURCE_SHA256" janet.c "$DS_JANET_HEADER_SHA256" janet.h \
    "$DS_JANET_SHELL_SHA256" shell.c | sha256sum -c - && \
    cc -std=c99 -O2 -DNDEBUG -I. janet.c shell.c -lm -ldl -pthread -o /janet

FROM base

COPY src/runtime/mise-assets.tsv /tmp/mise-assets.tsv
RUN case "$(dpkg --print-architecture)" in \
    arm64) platform=linux-arm64-musl ;; \
    amd64) platform=linux-x64-musl ;; \
    *) exit 1 ;; \
    esac && \
    sha=$(awk -F '\t' -v p="$platform" '$1 == p { print $2 }' /tmp/mise-assets.tsv) && \
    url=$(awk -F '\t' -v p="$platform" '$1 == p { print $3 }' /tmp/mise-assets.tsv) && \
    curl -fsSL --retry 3 -o /tmp/mise.tar.xz "$url" && \
    printf '%s  %s\n' "$sha" /tmp/mise.tar.xz | sha256sum -c - && \
    tar -xJf /tmp/mise.tar.xz -C /tmp && \
    install -m 0755 /tmp/mise/bin/mise /usr/local/bin/mise && \
    rm -rf /tmp/mise /tmp/mise.tar.xz /tmp/mise-assets.tsv
COPY --from=janet /janet /usr/local/bin/janet
# E2E tests drive the host engine through its mounted socket.
COPY --from=docker@sha256:018edbc908e08fcc9dbf029c812c34251e9b4719e6f71ca0e5eae2a987d014ca \
    /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker@sha256:018edbc908e08fcc9dbf029c812c34251e9b4719e6f71ca0e5eae2a987d014ca \
    /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins

# Janet comes from the pinned source above; mise installs the rest.
ENV MISE_DATA_DIR=/opt/mise MISE_CACHE_DIR=/tmp/mise-cache \
    MISE_DISABLE_TOOLS=janet MISE_TRUSTED_CONFIG_PATHS=/ \
    GOTOOLCHAIN=local
COPY .config/mise/config.toml /opt/ds-tools/mise.toml
RUN cd /opt/ds-tools && mise install && \
    for tool in go gofmt shellcheck shfmt taplo; do \
    ln -s "$(mise which "$tool")" "/usr/local/bin/$tool"; \
    done && \
    rm -rf /tmp/mise-cache /opt/mise/downloads && \
    chmod -R a+rX /opt/mise

# git refuses read-only mounts owned by another uid.
RUN git config --system --add safe.directory '*'

ENV DS_TEST_SANDBOX=1
USER ubuntu
