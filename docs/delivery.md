# Gitless delivery

`df` separates the controller checkout from the target runtime. The controller
builds and verifies artifacts; the target receives a pinned, self-contained
snapshot and does not need Git or a language toolchain.

## SSH controller

The preferred delivery path is:

```sh
./ds push my-host core
./ds push my-host remote --home .local/share/df-preview --dry-run
```

The controller:

1. probes the remote operating system and architecture;
2. selects matching Janet and mise runtimes;
3. Git-exports the Neovim and Tmux configuration sources;
4. builds a checksummed manifest;
5. derives a content-addressed version from the payload;
6. transfers files using SSH plus `mkdir`, `cat`, and `chmod`;
7. verifies and installs the snapshot before applying the layer.

Pushing identical content is idempotent and returns the existing version path.

## Build a snapshot manually

First prepare the runtimes:

```sh
mise run runtime:build
mise run runtime:fetch-mise
```

Then build for one supported platform:

```sh
bundle/build.sh \
  --version 1.0.0 \
  --platform macos-arm64 \
  --janet dist/runtime/bin/macos-arm64/janet \
  --mise dist/runtime/bin/macos-arm64/mise \
  --output /tmp/df-snapshot
```

The output contains `manifest.tsv`, `manifest.sha256`, a bootstrap entrypoint,
and the complete file payload.

Create a deterministic archive for manual transfer:

```sh
bundle/pack.sh \
  --snapshot /tmp/df-snapshot \
  --output /tmp/df-1.0.0.tar.gz
```

The packer writes both the archive and `/tmp/df-1.0.0.tar.gz.sha256`.

## Online pull

When a snapshot is served over HTTPS using its directory layout:

```sh
./pull.sh \
  --url https://example.invalid/df-snapshot \
  --manifest-sha256 MANIFEST_SHA256
```

Pull supports Curl and Wget, validates safe manifest paths and file modes, and
checks every payload digest when a SHA-256 utility is available. If the target
has no SHA-256 command, pull emits a warning and relies on TLS for transport
integrity.

## Installation layout

Snapshots install beneath:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/df/versions/<version>/
```

Incoming transfer data remains separate from immutable version directories.
Package and tool caches use their normal XDG/mise locations rather than the
version directory.
