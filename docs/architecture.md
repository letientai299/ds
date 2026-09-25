# Architecture

## Canonical model

`src/catalog.toml` is the source of truth for layers, component ownership,
command probes, and optional components. `src/scripts/generate.sh` resolves it
into Janet data under `src/scripts/generated/`; `mise run check` rejects stale
generated output.

Components have three ownership modes:

- `native`: installed through the host package manager and probed by command;
- `mise`: installed at a pinned version through the selected mise profile;
- `runtime`: delivered as part of the snapshot itself.

Layer order is deterministic. Validation rejects a layer — including the
`optional` list — that names an unknown component or repeats one, and rejects a
command claimed by two components. There is no dependency graph between
components; a layer is an ordered list, not a DAG.

## Runtime boundary

The shell entrypoint selects one of four delivered platforms:

- macOS ARM64;
- macOS x64;
- Linux ARM64 musl;
- Linux x64 musl.

Janet drives planning and convergence. mise supplies pinned tools and native
package bootstrap declarations. Delivered Linux Janet runtimes are static; the
same musl runtime executes on Alpine and common glibc distributions. Source
installation uses the host C compiler when `musl-gcc` is unavailable.

## Managed state

`ds` owns dedicated links under `~/.local/bin` and `~/.config/ds`, links the
selected Neovim/Tmux configuration, and inserts marked blocks into `.zshrc` and
`.gitconfig`.

Convergence distinguishes missing, present, conflicting, and unavailable state.
Exact-link and exact-marker checks prevent removal from deleting user content.
Marker operations refuse to follow symlinks, which prevents a linked rc file
from mutating another dotfiles repository.

An existing executable `~/.local/bin/mise` satisfies the managed mise command;
fresh hosts receive a link to the pinned delivered runtime.

Version directories are immutable, so managed links never point into one
directly: a delivered install links through `<prefix>/current`, a relative
symlink that bootstrap publishes and that convergence re-points at the version
being applied. Without it every link a previous version created would conflict
with the next one, and upgrading would be impossible. A checkout has no
`versions/` layout and links against the checkout itself.

## Docker planner

The `remote` layer uses this order:

1. reuse an engine when Docker, Buildx, and Compose are ready;
2. install rootless Docker on Linux when required tools, subordinate IDs, the
   user runtime directory, and user systemd are available;
3. report the missing capability;
4. permit rootful installation only through the explicit two-approval command.

A rootless engine is not considered persistent until user linger is enabled.
macOS engine or VM provisioning is outside the repository's scope.

## Repository layout

The repository root holds only the `ds` launcher, `docs/`, `src/`, `tests/`, and
`.config/`. A delivered snapshot uses the same shape — `ds` at the root and the
payload under `src/` — so `DS_ROOT` resolves identically in a checkout and on a
target.

| Path                       | Responsibility                                                |
| -------------------------- | ------------------------------------------------------------- |
| `ds`                       | Portable shell launcher and controller push dispatch          |
| `.config/mise/config.toml` | Development tools, pinned image digests, and every task       |
| `src/catalog.toml`         | Canonical layers and component metadata                       |
| `src/mise/`                | Payload mise profiles: pinned tools and native packages       |
| `src/scripts/`             | Janet planner, convergence engine, and generated catalog      |
| `src/runtime/`             | Reproducible Janet builds and pinned mise downloads           |
| `src/bundle/`              | Snapshot construction, packing, SSH push, controller, release |
| `src/dotfiles/`            | Portable Zsh and Git fragments                                |
| `src/lib/`                 | Shell helpers shared by controller-side scripts only          |
| `src/THIRD-PARTY.md`       | Notices that ship with the redistributed binaries             |
| `src/install.sh`           | Curl entrypoint that installs a published release             |
| `src/try.sh`               | Throwaway-container demo of a layer                           |
| `src/pull.sh`              | HTTPS transport for a served snapshot directory               |
| `src/bootstrap.sh`         | Manifest verification and version installation on a target    |
| `tests/`                   | Unit, contract, platform, and end-to-end coverage             |

`src/mise/` is a directory rather than root-level `mise*.toml` files so that
`MISE_GLOBAL_CONFIG_ROOT` can point at the payload profiles without colliding
with the development configuration under `.config/mise/`.

## Working from a checkout

A checkout supplies local edits to trial shells, source installation, Docker
images, delivery bundles, and SSH pushes. The [source installer][source-installer]
finds the enclosing checkout from the current directory. It reuses local edits
without pulling or resetting them:

```sh
sh scripts/install.sh --no-apply
sh scripts/install.sh --shell
```

The first command prepares the sources and runtimes and previews `core`; the
second applies it and opens Zsh. `--no-apply` still installs build prerequisites
and downloads sources. Neovim and Tmux configuration come from sibling
`nvim.conf` and `tmux.conf` checkouts by default. Set `DS_NVIM_SOURCE` or
`DS_TMUX_SOURCE` to use other directories.

### Trial shell

Link the launcher from the checkout, then open an isolated shell from any
working directory:

```sh
mkdir -p ~/.local/bin
ln -s "$PWD/ds" ~/.local/bin/ds
exec ~/.local/bin/ds
```

`ds shell` starts the same environment without replacing the current shell.
It uses the checkout's Zsh, Git, and Neovim configuration without installing
packages or editing the normal startup files. Trial state lives under
`${XDG_STATE_HOME:-~/.local/state}/ds/shell`. Apply a layer inside that shell
with `ds apply core`; it updates the isolated configuration and command links.

The checkout can also build a reusable Ubuntu trial image. It mounts the
current directory at `/work` and removes the container on exit:

```sh
ds shell --docker
```

Run `ds shell --docker --rebuild` after changing the checkout.
[Docker trial details][try] describe the container's filesystem behavior.

### SSH delivery

Copy the source installer to a host when that host should clone `main` itself:

```sh
scp scripts/install.sh my-host:ds-install.sh
ssh -t my-host 'sh ~/ds-install.sh --layer remote --no-apply'
ssh -t my-host 'sh ~/ds-install.sh --layer remote'
```

Use `--skip docker` on a host without a Docker engine.

Preview the `remote` layer inside an isolated home before applying it to a
normal SSH host:

```sh
./ds push my-host remote --home .local/share/ds-preview --dry-run
./ds push my-host remote
```

Use `./ds push my-host remote --force --dry-run` and then
`./ds push my-host remote --force` to back up and replace conflicting remote
configuration. The controller probes the target, builds a snapshot,
transfers and verifies it, then applies the selected layer. The target needs
POSIX shell utilities and `uname` for platform detection. See
[Gitless delivery][delivery] for the bundle format and prerequisites.

### Development and verification

The checkout needs [mise][mise], Git, a C toolchain, and Docker for the full
runtime matrix. Link the development configuration at the checkout root so
mise runs tasks from that directory:

```sh
ln -s .config/mise/config.toml mise.toml
mise install
mise run runtime:build
mise run runtime:fetch-mise
mise run check
mise run try
mise run e2e:all
mise run verify
```

`mise run try` builds a snapshot and opens an uncached trial container.
`e2e:all` runs the end-to-end targets. `verify` also checks runtime
reproducibility and platform execution. See [Testing][testing] for test scope.

[source-installer]: ../scripts/install.sh
[try]: try.md
[delivery]: delivery.md
[mise]: https://mise.jdx.dev/
[testing]: testing.md
