FROM ubuntu:latest

ENV HOME=/root \
    DEBIAN_FRONTEND=noninteractive \
    PATH=/root/.local/bin:/root/.local/share/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

COPY snapshot /snapshot
RUN set -eu; \
    installed=$(/snapshot/bootstrap.sh --source /snapshot \
      --prefix "$HOME/.local/share/ds" \
      --manifest-sha256 "$(cat /snapshot/manifest.sha256)"); \
    "$installed/ds" apply core; \
    ds status core --check; \
    rm -rf /snapshot /var/lib/apt/lists/*

WORKDIR /work
ENTRYPOINT ["/bin/zsh", "-fc", "source \"$HOME/.config/ds/shell.zsh\"; exec \"$@\"", "ds-docker"]
CMD ["zsh", "-il"]
