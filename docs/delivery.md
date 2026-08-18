# Gitless delivery

`ds` separates the controller checkout from the target runtime. The controller
builds and verifies artifacts; the target receives a pinned, self-contained
snapshot and does not need Git or a language toolchain.

Four transports deliver the same verified snapshot: a published release over
HTTPS, an SSH push from a controller checkout, a served snapshot directory, and
a manual archive.

## Published release

A release carries one archive per platform plus the two entrypoint scripts. The
asset names omit the version so that `releases/latest/download/<asset>` resolves
without an API call, a token, or `jq`:

```text
ds-linux-arm64-musl.tar.gz   ds-macos-arm64.tar.gz   install.sh
ds-linux-x64-musl.tar.gz     ds-macos-x64.tar.gz     try.sh
```

Build every archive from a checkout:

```sh
mise run release --version v1.0.0
```

The task writes `dist/release/v1.0.0/`. Publish it with the [GitHub CLI][gh]:

```sh
gh release create v1.0.0 dist/release/v1.0.0/* --generate-notes
```

Targets then install with a single command. `install.sh` detects the platform,
verifies the archive checksum, hands the extracted snapshot to `bootstrap.sh` —
which re-verifies the manifest and every payload digest — and applies a layer:

```sh
curl -fsSL https://github.com/letientai299/ds/releases/latest/download/install.sh | sh
```

Point `--release-url` at any static host serving the same asset names to use a
mirror instead of GitHub.

## SSH controller

The preferred delivery path is:

```sh
./ds push my-host core
./ds push my-host remote --home .local/share/ds-preview --dry-run
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
src/bundle/build.sh \
  --version 1.0.0 \
  --platform macos-arm64 \
  --janet dist/runtime/bin/macos-arm64/janet \
  --mise dist/runtime/bin/macos-arm64/mise \
  --output /tmp/ds-snapshot
```

The output contains `manifest.tsv`, `manifest.sha256`, a bootstrap entrypoint,
and the complete file payload under `files/`. That payload mirrors a checkout —
the `ds` launcher at the top and everything else under `src/` — so `DS_ROOT`
means the same thing on a target as it does in the repository.

Create a deterministic archive for manual transfer:

```sh
src/bundle/pack.sh \
  --snapshot /tmp/ds-snapshot \
  --output /tmp/ds-1.0.0.tar.gz
```

The packer writes both the archive and `/tmp/ds-1.0.0.tar.gz.sha256`.

## Online pull

When a snapshot is served over HTTPS using its directory layout:

```sh
./src/pull.sh \
  --url https://example.invalid/ds-snapshot \
  --manifest-sha256 MANIFEST_SHA256
```

Pull supports Curl and Wget, validates safe manifest paths and file modes, and
checks every payload digest when a SHA-256 utility is available. If the target
has no SHA-256 command, pull emits a warning and relies on TLS for transport
integrity.

## Installation layout

Snapshots install beneath:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/ds/versions/<version>/
```

Incoming transfer data remains separate from immutable version directories.
Package and tool caches use their normal XDG/mise locations rather than the
version directory.

[gh]: https://cli.github.com/
