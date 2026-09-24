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

Packing writes a `.sha256` sidecar beside each archive, so a release carries
four more assets than the names above.

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
6. streams a verified file list over SSH when `tar` is available, or transfers
   individual files using `mkdir`, `cat`, and `chmod`;
7. verifies and installs the snapshot before applying the layer.

Pushing identical content is idempotent and returns the existing version path.

## Build a snapshot manually

First prepare the runtimes:

```sh
mise run runtime:build
mise run runtime:fetch-mise
```

The controller uses the pinned Go toolchain to build the Kitty launcher and
Taplo to resolve layer definitions. Target hosts need neither tool.

Then build for one supported platform:

```sh
mise exec -- src/bundle/build.sh \
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
checks the manifest and every payload digest against `--manifest-sha256` before
running the delivered `bootstrap.sh`. Because that pin is mandatory, pull fails
when the target has no SHA-256 command rather than falling back to transport
trust. Its staging directory is removed on exit, including on failure.

## Installation layout

Snapshots install beneath:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/ds/versions/<version>/
```

Bootstrap stages an install beside its version directory and publishes it with
a same-directory rename, so a version directory is either absent or complete.
Pull removes its incoming transfer data on exit. SSH push retains its incoming
snapshot under `<prefix>/incoming/<version>`.

Staging leaves `<prefix>/current` untouched. This applies to bootstrap, pull,
`install.sh --no-apply`, `push --deliver-only`, and `push --dry-run`. Managed links
resolve through `current`; a candidate's preview checks its own sources without
switching live links.

Applying a staged candidate installs packages and writes its managed files
before atomically switching `current`. The old link is retained as `previous`.
An explicit switch is also available:

```sh
ds stage --source /tmp/ds-snapshot --prefix ~/.local/share/ds \
  --manifest-sha256 MANIFEST_SHA256
~/.local/share/ds/versions/1.0.0/ds apply core --dry-run
~/.local/share/ds/versions/1.0.0/ds apply core
ds activate 1.0.0 --dry-run
ds rollback --dry-run
ds rollback
```

`activate` and `rollback` switch version links only; they do not install or
uninstall packages or undo managed-file edits. Use a candidate's `apply` when
its package or file plan must also run. `--prefix DIR` selects a different
installation; otherwise the running delivered version determines the prefix,
or a checkout defaults to `${XDG_DATA_HOME:-$HOME/.local/share}/ds`.

Staging and mutations serialize through `<prefix>/.mutation-lock`. Contention
fails immediately. The current symlink is replaced with a same-directory rename,
so readers see either complete version. A failed package or file action leaves
current unchanged, but earlier package or file actions may have completed; fix
the reported problem and retry the candidate. Adoption backups remain available.
Docker provisioning retains its existing advisory diagnostics; use `status
remote --check` to require full readiness.

A killed process can leave a lock or hidden incoming directory. Confirm that no
installation process is running before removing that specific stale lock or
incoming directory. Completed versions and `current` remain intact. If a crash
happens after `previous` is recorded but before switching `current`, both links
can name the old version; retry activation of the intended candidate.

Payload verification feeds all validated digest records to one checksum
process. Tools without check mode fall back to individual checks. Hosts without
a checksum tool retain the existing controller-verification warning; pull still
requires a local checksum tool.
Package and tool caches use their normal XDG/mise locations rather than the
version directory.

[gh]: https://cli.github.com/
