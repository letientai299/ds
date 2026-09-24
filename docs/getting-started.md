# Getting started

## Look before installing

[Try ds in Docker][try] applies a layer inside a throwaway container and
opens a shell in it. Nothing is written to your home, so it answers "what does
this feel like" without a decision.

## Install

Follow [Install from main][install-main] for macOS, Ubuntu, Debian, or Alpine,
including a running container. `scripts/install.sh --no-apply` prepares sources
and runtimes, then previews `core`. Without that flag it applies the layer.
The installer uses the project containing the current directory, or clones
`main` outside a checkout. This path needs no published `ds` release.

### Published releases

The following alternative requires a published release with installer and
platform archive assets. It needs Curl or Wget and tar on the target, but no
checkout, Git, Janet, or mise:

```sh
curl -fsSL \
  https://github.com/letientai299/ds/releases/latest/download/install.sh | sh
```

Useful flags. All except `--no-apply` also read a `DS_`-prefixed environment
variable:

| Flag                | Effect                                                    |
| ------------------- | --------------------------------------------------------- |
| `--layer remote`    | Apply `remote` instead of `core`                          |
| `--no-apply`        | Install the version directory without converging anything |
| `--version v1.2.3`  | Pin a release tag instead of the latest                   |
| `--prefix DIR`      | Install somewhere other than `~/.local/share/ds`          |
| `--platform NAME`   | Skip `uname` detection                                    |
| `--release-url URL` | Use a mirror instead of GitHub releases                   |

Reinstalling the same release is a no-op: version directories are immutable and
content-addressed, so the installer reuses an existing one.

## Prepare a checkout

A checkout supports source installation, development, and SSH delivery. It runs
on macOS and Linux on ARM64 and x64, and building the complete runtime matrix
requires mise, Git, a C toolchain, and Docker.

```sh
mise install
mise run runtime:build
mise run runtime:fetch-mise
mise run check
```

The first command installs development tooling from `.config/mise/config.toml`,
which also defines every task. Runtime tasks build Janet and fetch mise for
macOS and Linux, ARM64 and x64.

A checkout expects these configuration sources, each a Git checkout with a
`HEAD` to export:

- `../nvim.conf`, or a path supplied through `DS_NVIM_SOURCE`;
- `../tmux.conf`, or a path supplied through `DS_TMUX_SOURCE`.

Both are required for any snapshot build, whatever layer you intend to apply, so
`mise run try`, `mise run release`, and `ds push` all fail without them.
Delivery bundles contain committed Git exports of both sources.

## Apply core safely

`ds status` and `ds apply` use the saved layer, initially `core`.
Choose an explicit layer to inspect or apply another preset:

```sh
./ds status core
./ds apply core --dry-run
```

State has three useful summaries:

- `complete`: every component and managed file is present;
- `incomplete`: one or more entries are missing or unavailable;
- `conflict`: a managed target exists with different ownership or content.

Apply refuses conflicts:

```sh
./ds apply core
```

If a conflict should be preserved and replaced, use `--force`:

```sh
./ds apply core --force --dry-run
./ds apply core --force
```

Each conflicting target is backed up to `<target>.ds-adopted` before it is
replaced. `--force` never follows a linked Zsh rc into another repository.

## Use the remote layer

`remote` is an extended local preset. It includes every `core` component
and adds the tools listed under [Layers][layers]. SSH delivery uses
`ds push HOST LAYER`:

```sh
./ds apply remote --dry-run
./ds apply remote
./ds status remote --verbose
```

On macOS, Docker must already be available through Docker Desktop, OrbStack, or
another compatible engine. On Linux, apply reuses a ready engine or selects the
rootless path when the required user-namespace and systemd capabilities exist.

Skip Docker only on a deliberately restricted host:

```sh
./ds apply remote --skip docker
```

The layer remains incomplete until Docker is ready.

## Optional Starship prompt

```sh
./ds apply starship --dry-run
./ds apply starship
./ds status starship
```

Remove the selection with:

```sh
./ds remove starship
```

## Recovery

```sh
./ds remove core
```

Removal deletes only exact links and marker blocks owned by `ds`. It restores
available `.ds-adopted` backups when the original target is absent. Installed
system packages, mise tools, and versioned snapshots are additive and remain on
disk.

`--force` refuses to overwrite an existing `.ds-adopted` backup.

[install-main]: ../README.md#install-from-main
[layers]: ../README.md#layers
[try]: try.md
