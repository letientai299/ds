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
| `core`   | mise, Git, Curl, Zsh, Neovim, fd, FZF, ripgrep, nnn, jq, and xh  |
| `remote` | `core` plus Tmux, [Docker][docker] readiness, Zoxide, Bat, Delta |
| optional | Starship, enabled independently with `ds add starship`           |

`src/catalog.toml` is the source of truth for this table, and `ds status LAYER`
prints what a layer actually resolves to on a given machine.

Mise manages the pinned Neovim release directly. Alpine builds that release from
checksum-verified source during installation; macOS and glibc Linux use upstream
binaries. Later applies reuse the installed version.

Neovim and Tmux configuration come from sibling `nvim.conf` and `tmux.conf`
checkouts by default. A delivered snapshot contains Git-exported copies, so the
target does not need those repositories.

## Try it first

Nothing is written to your home. The demo builds a snapshot, applies it inside a
throwaway container, and hands over an interactive Zsh:

```sh
curl -fsSL https://raw.githubusercontent.com/letientai299/ds/main/src/try.sh | sh
```

See [Try ds in Docker][try] for what to look at once the prompt appears,
how to try the `remote` layer, and how to run the demo from a checkout.

## Quick start

For daily use from a checkout, link the launcher once:

```sh
mkdir -p ~/.local/bin
ln -s "$PWD/ds" ~/.local/bin/ds
```

From any working directory, replace the current shell with the trial environment:

```sh
exec ~/.local/bin/ds
```

`ds shell` does the same; omit `exec` to return with `exit`. The trial uses
`core`, retains your home and working directory, and loads this checkout's Zsh,
Git, and Neovim configuration. It reuses installed tools without installing
packages or editing your startup files. Other application configurations remain
available through links, so their edits still affect the originals. Trial state
and history live under `${XDG_STATE_HOME:-~/.local/state}/ds/shell`.
Open a new terminal to return to your normal setup. Use `ds --help` for commands.

### Install a release

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

Installer flags are documented in [Getting started and recovery][getting-started]; the release layout is in [Gitless delivery][delivery].

Normal apply refuses conflicting managed targets. To preserve and replace
conflicts, preview adoption first:

```sh
ds adopt core --dry-run
ds adopt core
```

Adoption backs each conflict up to `<target>.ds-adopted` before replacing it.
Marked blocks in `~/.zshrc` and `~/.gitconfig` are rewritten in place instead,
so the rest of those files survives either takeover. See
[Conflict operations][conflict-ops].

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
needs only POSIX `sh`, `mkdir`, `cat`, `chmod`, `rm`, `mv`, and `ln` for delivery,
plus `uname` for automatic platform detection.

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

## License

[MIT][license]. Snapshots redistribute the pinned Janet and mise binaries; their
notices ship with every archive in [`src/THIRD-PARTY.md`][third-party].

## Documentation

- [Try ds in Docker][try]
- [Getting started and recovery][getting-started]
- [Command reference][cli]
- [Gitless delivery][delivery]
- [Architecture][architecture]
- [Testing][testing]

[alpine]: https://alpinelinux.org/
[architecture]: docs/architecture.md
[cli]: docs/cli.md
[conflict-ops]: docs/cli.md#conflict-operations
[delivery]: docs/delivery.md
[docker]: https://www.docker.com/
[getting-started]: docs/getting-started.md
[janet]: https://janet-lang.org/
[license]: LICENSE
[mise]: https://mise.jdx.dev/
[rocky]: https://rockylinux.org/
[testing]: docs/testing.md
[third-party]: src/THIRD-PARTY.md
[try]: docs/try.md
[ubuntu]: https://ubuntu.com/
