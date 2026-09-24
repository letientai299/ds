# ds

`ds` is a portable, layered dotfiles deployment system for macOS and Linux. It
installs a small daily environment locally or on a Gitless SSH host without
requiring a language runtime on the target.

The repository ships pinned [Janet][janet] and [mise][mise] runtimes,
checksum-verified delivery bundles, conflict-aware file management, and isolated
end-to-end tests across [Alpine][alpine], [Ubuntu][ubuntu], [Rocky
Linux][rocky], and macOS.

## Layers

Run `ds help` for the component lists generated from the catalog.
`remote` extends `core`; `extra` and `ui` are independent. `all` combines every
layer without duplicating tools.

`src/catalog.toml` defines the layers. `ds status LAYER --verbose` shows
resolved components and managed files. `remote` is an extended local preset;
SSH delivery uses `ds push HOST LAYER`.

Mise manages the pinned Neovim release directly. Alpine builds that release from
checksum-verified source during installation; macOS and glibc Linux use upstream
binaries. Later applies reuse the installed version.

Neovim and Tmux configuration come from sibling `nvim.conf` and `tmux.conf`
checkouts by default. A delivered snapshot contains Git-exported copies, so the
target does not need those repositories.

## Try it first

With the global launcher linked to this checkout, run `ds shell --docker` from any
project directory. It builds a reusable Ubuntu image with `core` installed,
mounts the current directory at `/work`, and removes the container on exit.
Use `ds shell --docker --rebuild` to refresh the image and capture checkout changes.

From this checkout, install `main` inside a disposable Ubuntu container and
open Zsh:

```sh
docker run --rm -it \
  -v "$PWD/scripts/install.sh:/install.sh:ro" \
  ubuntu:24.04 sh /install.sh --shell
```

Only the installer is mounted. The cloned sources, tools, and configuration
stay inside the container. Use `--no-apply` instead of `--shell` to preview.
Inside an existing container with this checkout mounted at `/work`, run
`sh /work/scripts/install.sh` from `/work` to use the mounted checkout.

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
`core` initially, retains your home and working directory, and loads this
checkout's Zsh, Git, and Neovim configuration. It reuses installed tools without
installing packages or editing your startup files. Other application
configurations remain available through links, so their edits still affect the
originals. Trial state and history live under
`${XDG_STATE_HOME:-~/.local/state}/ds/shell`. Its persistent `ZDOTDIR` is the
`zsh` directory there; local additions to its `.zshrc` survive new sessions.
Running `ds apply core` inside this shell installs packages and updates its
isolated configuration and command links. Your normal `.zshrc` and `.gitconfig`
remain unchanged. Layer and component selections persist too. Open a new
terminal to return to your normal setup. Use `ds --help` for everyday commands
and `ds help --all` for advanced operations. `ds apply` and `ds status` use the
selected layers, initially `core`; status and previews identify the active
configuration scope.

### Install from main

Run the [source installer][source-installer] on macOS, Ubuntu, Debian, or Alpine:

```sh
sh scripts/install.sh --no-apply
sh scripts/install.sh --shell
```

The first command prepares the checkout and previews `core`. The second applies
`core` and opens Zsh. Omit `--shell` to install without opening a shell.
`--no-apply` still installs build prerequisites and downloads sources and
runtimes; it does not apply dotfiles or install the layer's tools.

The installer finds this project by walking up from the current directory.
From a subdirectory, invoke the script by its relative or absolute path. Outside
this project, it clones `main` under
`${XDG_DATA_HOME:-~/.local/share}/ds-source`, or `--prefix DIR`. Existing
checkouts and their local edits are reused without pulling or resetting them.
Keep the sources: managed files link to them.

For a new machine, copy `scripts/install.sh` there and run `sh install.sh`.
The standalone script installs missing Linux prerequisites using root or
`sudo`, fetches checksum-verified runtimes, builds Janet if needed, and clones
missing sibling Neovim and Tmux configurations. No `ds` release or Docker engine
is needed. macOS needs Command Line Tools (`xcode-select --install`) and
[Homebrew][brew] for applying packages. `DS_NVIM_SOURCE` and `DS_TMUX_SOURCE`
can select existing configuration directories.

To install on an SSH host from this checkout:

```sh
scp scripts/install.sh my-host:ds-install.sh
ssh -t my-host 'sh ~/ds-install.sh --layer remote --no-apply'
ssh -t my-host 'sh ~/ds-install.sh --layer remote'
```

Use `--skip docker` with `--layer remote` on restricted hosts or containers.
See `sh scripts/install.sh --help` for options. After applying, the launcher is
available at `~/.local/bin/ds`.

For development and portable delivery bundles, see [Working on ds][working-on-ds]
and [Prepare a checkout][prepare-checkout]. Published release packaging remains
in [Gitless delivery][delivery].

Normal apply refuses conflicting managed targets. To preserve and replace
conflicts, preview with `--force` first:

```sh
ds apply core --force --dry-run
ds apply core --force
```

`--force` backs each conflict up to `<target>.ds-adopted` before replacing it.
Marked blocks in `~/.zshrc` and `~/.gitconfig` are rewritten in place instead,
so the rest of those files survives the takeover. See
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

To back up and replace conflicting remote configuration:

```sh
./ds push my-host remote --force --dry-run
./ds push my-host remote --force
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
`ds` launcher, `scripts/`, `docs/`, `src/`, and `tests/`. A delivered snapshot
uses the same shape, so `DS_ROOT` means one thing in both.

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
[brew]: https://brew.sh/
[cli]: docs/cli.md
[conflict-ops]: docs/cli.md#conflict-operations
[delivery]: docs/delivery.md
[docker]: https://www.docker.com/
[getting-started]: docs/getting-started.md
[prepare-checkout]: docs/getting-started.md#prepare-a-checkout
[janet]: https://janet-lang.org/
[license]: LICENSE
[mise]: https://mise.jdx.dev/
[rocky]: https://rockylinux.org/
[source-installer]: scripts/install.sh
[testing]: docs/testing.md
[third-party]: src/THIRD-PARTY.md
[try]: docs/try.md
[ubuntu]: https://ubuntu.com/
[working-on-ds]: #working-on-ds
