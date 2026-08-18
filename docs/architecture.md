# Architecture

## Canonical model

`catalog.toml` is the source of truth for layers, component ownership, command
probes, and optional components. `scripts/generate.sh` resolves it into Janet
data under `scripts/generated/`; `mise run check` rejects stale generated
output.

Components have three ownership modes:

- `native`: installed through the host package manager and probed by command;
- `mise`: installed at a pinned version through the selected mise profile;
- `runtime`: delivered as part of the snapshot itself.

Layer order is deterministic, duplicate command ownership is rejected, and an
unknown component or dependency cycle fails validation.

## Runtime boundary

The shell entrypoint selects one of four delivered platforms:

- macOS ARM64;
- macOS x64;
- Linux ARM64 musl;
- Linux x64 musl.

Janet drives planning and convergence. mise supplies pinned tools and native
package bootstrap declarations. Linux Janet runtimes are static; the same musl
runtime executes on Alpine and common glibc distributions.

## Managed state

`df` owns dedicated links under `~/.local/bin` and `~/.config/df`, links the
selected Neovim/Tmux configuration, and inserts marked blocks into `.zshrc` and
`.gitconfig`.

Convergence distinguishes missing, present, conflicting, and unavailable
state. Exact-link and exact-marker checks prevent unapply from deleting user
content. Marker operations refuse to follow symlinks, which prevents a linked
rc file from mutating another dotfiles repository.

An existing executable `~/.local/bin/mise` satisfies the managed mise command;
fresh hosts receive a link to the pinned delivered runtime.

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

| Path           | Responsibility                                                 |
| -------------- | -------------------------------------------------------------- |
| `ds`           | Portable shell launcher and controller push dispatch           |
| `catalog.toml` | Canonical layers and component metadata                        |
| `mise*.toml`   | Pinned tools, native packages, optional profiles, and tasks    |
| `scripts/`     | Janet planner, convergence engine, and generated catalog       |
| `runtime/`     | Reproducible Janet builds and pinned mise downloads            |
| `bundle/`      | Snapshot construction, packing, SSH push, and controller logic |
| `dotfiles/`    | Portable Zsh and Git fragments                                 |
| `tests/`       | Unit, contract, platform, and end-to-end coverage              |
