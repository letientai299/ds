# df

`df` is a portable, layered dotfiles deployment system for macOS and Linux.
It installs a small daily environment locally or on a Gitless SSH host without
requiring a language runtime on the target.

The repository ships pinned Janet and mise runtimes, checksum-verified delivery
bundles, conflict-aware file management, and isolated end-to-end tests across
Alpine, Ubuntu, Rocky Linux, and macOS.

## Layers

| Layer    | Contents                                                   |
| -------- | ---------------------------------------------------------- |
| `core`   | Git, Curl, Zsh, Neovim, fd, FZF, ripgrep, nnn, jq, and xh  |
| `remote` | `core` plus Tmux, Docker readiness, Zoxide, Bat, and Delta |
| optional | Starship, enabled independently with `ds add starship`     |

Neovim and Tmux configuration come from sibling `nvim.conf` and `tmux.conf`
checkouts by default. A delivered snapshot contains Git-exported copies, so the
target does not need those repositories.

## Quick start

Install the development tools and build the pinned runtime payloads:

```sh
mise install
mise run runtime:build
mise run runtime:fetch-mise
```

Inspect and preview before changing the current home:

```sh
./ds doctor core
./ds diff core
./ds apply core --dry-run
```

Apply only when the preview is expected:

```sh
./ds apply core
```

Normal apply refuses conflicting managed targets. To preserve and replace
conflicts, preview adoption first:

```sh
./ds adopt core --dry-run
./ds adopt core
```

Adoption moves each conflict to `<target>.df-adopted`; `ds unapply` restores
that backup. `ds force` is destructive and does not create backups.

## Remote delivery

Push and preview `remote` inside an isolated home on an SSH host:

```sh
./ds push my-host remote --home .local/share/df-preview --dry-run
```

Apply to the normal remote home after reviewing the preview:

```sh
./ds push my-host remote
```

The controller probes the target platform, creates a content-addressed bundle,
transfers it over SSH, verifies it, and applies the selected layer. The target
needs only POSIX `sh`, `mkdir`, `cat`, and `chmod` for delivery, plus `uname`
for automatic platform detection.

## Verification

```sh
mise run check
mise run e2e:all
mise run verify
```

`e2e:all` launches all seven E2E targets concurrently. The broader `verify`
task also checks runtime reproducibility and platform execution.

## Documentation

- [Getting started and recovery](docs/getting-started.md)
- [Command reference](docs/cli.md)
- [Gitless delivery](docs/delivery.md)
- [Architecture](docs/architecture.md)
- [Testing](docs/testing.md)
