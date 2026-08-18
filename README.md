# ds

`ds` is a portable, layered dotfiles deployment system for macOS and Linux. It
installs a small daily environment locally or on a Gitless SSH host without
requiring a language runtime on the target.

The repository ships pinned [Janet][janet] and [mise][mise] runtimes,
checksum-verified delivery bundles, conflict-aware file management, and isolated
end-to-end tests across [Alpine][alpine], [Ubuntu][ubuntu], [Rocky
Linux][rocky], and macOS.

## Layers

| Layer    | Contents                                                         |
| -------- | ---------------------------------------------------------------- |
| `core`   | Git, Curl, Zsh, Neovim, fd, FZF, ripgrep, nnn, jq, and xh        |
| `remote` | `core` plus Tmux, [Docker][docker] readiness, Zoxide, Bat, Delta |
| optional | Starship, enabled independently with `ds add starship`           |

Neovim and Tmux configuration come from sibling `nvim.conf` and `tmux.conf`
checkouts by default. A delivered snapshot contains Git-exported copies, so the
target does not need those repositories.

## Try it first

Nothing is written to your home. The demo builds a snapshot, applies it inside a
throwaway container, and hands over an interactive Zsh:

```sh
curl -fsSL https://raw.githubusercontent.com/letientai299/ds/main/src/try.sh | sh
```

See [Try ds in Docker](docs/try.md) for what to look at once the prompt appears,
how to try the `remote` layer, and how to run the demo from a checkout.

## Quick start

Install the latest release into your own home. No checkout, no Git, and no
language runtime on the machine:

```sh
curl -fsSL https://github.com/letientai299/ds/releases/latest/download/install.sh | sh
```

The installer detects the platform, downloads the matching release archive,
verifies its checksum and every payload digest, installs an immutable version
directory under `~/.local/share/ds`, and applies `core`.

To preview instead of applying, install without converging and use the normal
commands:

```sh
curl -fsSL https://github.com/letientai299/ds/releases/latest/download/install.sh | sh -s -- --no-apply
~/.local/share/ds/versions/*/ds diff core
~/.local/share/ds/versions/*/ds apply core --dry-run
```

Installer options are documented in [Gitless delivery](docs/delivery.md).

Normal apply refuses conflicting managed targets. To preserve and replace
conflicts, preview adoption first:

```sh
ds adopt core --dry-run
ds adopt core
```

Adoption moves each conflict to `<target>.ds-adopted`; `ds unapply` restores
that backup. `ds force` is destructive and does not create backups.

## Remote delivery

Push and preview `remote` inside an isolated home on an SSH host:

```sh
./ds push my-host remote --home .local/share/ds-preview --dry-run
```

Apply to the normal remote home after reviewing the preview:

```sh
./ds push my-host remote
```

The controller probes the target platform, creates a content-addressed bundle,
transfers it over SSH, verifies it, and applies the selected layer. The target
needs only POSIX `sh`, `mkdir`, `cat`, and `chmod` for delivery, plus `uname`
for automatic platform detection.

## Working on ds

A checkout needs mise, Git, a C toolchain, and Docker. Development tooling and
every task live in `.config/mise/config.toml`:

```sh
mise install
mise run runtime:build
mise run runtime:fetch-mise
mise run check
```

The payload itself lives under `src/`, which keeps the repository root to the
`ds` launcher, `docs/`, `src/`, and `tests/`. A delivered snapshot uses the same
shape, so `DS_ROOT` means one thing in both.

## Verification

```sh
mise run check
mise run e2e:all
mise run verify
```

`e2e:all` launches every E2E target concurrently. The broader `verify` task also
checks runtime reproducibility and platform execution.

## Documentation

- [Try ds in Docker](docs/try.md)
- [Getting started and recovery](docs/getting-started.md)
- [Command reference](docs/cli.md)
- [Gitless delivery](docs/delivery.md)
- [Architecture](docs/architecture.md)
- [Testing](docs/testing.md)

[alpine]: https://alpinelinux.org/
[docker]: https://www.docker.com/
[janet]: https://janet-lang.org/
[mise]: https://mise.jdx.dev/
[rocky]: https://rockylinux.org/
[ubuntu]: https://ubuntu.com/
