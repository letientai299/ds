# Getting started

## Look before installing

[Try ds in Docker][try] applies a layer inside a throwaway container and
opens a shell in it. Nothing is written to your home, so it answers "what does
this feel like" without a decision.

## Install

Installing a published release needs neither a checkout nor Git, Janet, mise, or
a preinstalled downloader on the target:

```sh
curl -fsSL https://github.com/letientai299/ds/releases/latest/download/install.sh | sh
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

A checkout is needed only to develop `ds` or to push to an SSH host. It supports
macOS and Linux on ARM64 and x64, and building the complete runtime matrix
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

Always inspect the current state first:

```sh
./ds status core
./ds diff core
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

If a conflict should be preserved and replaced, use adoption:

```sh
./ds adopt core --dry-run
./ds adopt core
```

Each conflicting target is backed up to `<target>.ds-adopted` before it is
replaced. Adoption never follows a linked Zsh rc into another repository.

## Use the remote layer

`remote` includes every `core` component and adds the tools listed under
[Layers][layers]:

```sh
./ds apply remote --dry-run
./ds apply remote
./ds doctor remote
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
./ds add starship --dry-run
./ds add starship
./ds status starship
```

Remove the selection with:

```sh
./ds unapply starship
```

## Recovery

```sh
./ds unapply core
```

Unapply removes only exact links and marker blocks owned by `ds`. It restores
available `.ds-adopted` backups when the original target is absent. Installed
system packages, mise tools, and versioned snapshots are additive and remain on
disk.

Avoid `ds force` unless discarding each reported conflict is intentional. It
removes conflicting targets without backups.

[layers]: ../README.md#layers
[try]: try.md
