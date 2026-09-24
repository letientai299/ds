# Try ds in Docker

`ds shell --docker` opens a provisioned Ubuntu container with your current directory
mounted read-write at `/work`:

```sh
ds shell --docker
```

The first run builds from `ubuntu:latest` and installs `core`, including `nnn`.
Later runs reuse the local image without rebuilding or downloading packages.
`exit` removes the container. Edits under `/work` remain on the host; changes
elsewhere in the container are discarded. The shell runs as root, so files
created in `/work` may be root-owned on Linux hosts.

Refresh Ubuntu, packages, and the checkout configuration explicitly:

```sh
ds shell --docker --rebuild
```

The image captures this checkout when built; source edits require a rebuild.
The command needs the checkout's pinned Linux runtimes and sibling configuration
repositories, just like `mise run try`. Docker must access the current directory
on the host. For scripted runs, pass a command after `--`:

```sh
ds shell --docker -- ds status core --check
```

## Uncached demo

`src/try.sh` builds a snapshot, applies a layer inside a throwaway
[container][docker], and hands over an interactive login Zsh. Nothing touches
your own home, and the container disappears on exit.

## Without a checkout

```sh
curl -fsSL https://raw.githubusercontent.com/letientai299/ds/main/src/try.sh | sh
```

The container installs the latest release with
[`src/install.sh`][install-sh], applies `core`, then opens Zsh. Only
Docker is needed on the host.

## From a checkout

```sh
mise run try
```

This packs the working tree into a snapshot instead of downloading a release, so
it reflects uncommitted changes. It needs the pinned runtimes; see the working
notes in the [README][readme]. Force either payload source explicitly:

```sh
./src/try.sh --source checkout
./src/try.sh --source release --version v1.0.0
```

`--version` selects both the installer and its payload. `--platform` selects
matching container and snapshot architectures, for example `linux/amd64` when
trying an x64 target from an ARM64 host. Checkout snapshots are removed when
the container exits, including on failure.

## What to look at

Once the prompt appears, the container is a normal target: the managed `.zshrc`
marker has loaded [`src/dotfiles/shell.zsh`][shell-zsh], and
every layer component is on `PATH`.

```sh
ds status                  # health and problems
ds status --verbose        # full state and diagnostics
ls -l ~/.config/ds    # the dedicated files ds owns
cat ~/.zshrc          # the marker block ds inserted
```

The prompt, history behaviour, aliases, and the `n` wrapper for `nnn` are the
daily-driver surface. Open Neovim with `vi` to see the linked configuration, and
try `fzf`, `rg`, `fd`, and `jq` directly.

Preview commands answer the question that matters before adopting `ds` on a real
machine — what would it change?

```sh
ds apply core --dry-run
ds remove core       # remove everything ds owns, then look around again
```

## Other layers and images

`remote` adds Tmux, Zoxide, Bat, and Delta. Docker readiness stays incomplete
inside a container without a reachable engine, which is expected:

```sh
./src/try.sh --layer remote
```

The demo defaults to Ubuntu. Any image with a supported package manager works,
which is a quick way to see how native package selection differs:

```sh
./src/try.sh --image alpine:3.21
./src/try.sh --image rockylinux:9
```

## Non-interactive runs

`--command` replaces the interactive shell, which is useful for a scripted look
at the result. Zsh reads `.zshrc` only when interactive, so a non-interactive
command has to source the fragment itself:

```sh
./src/try.sh --command 'zsh -fc "source \$HOME/.config/ds/shell.zsh; command -v rg fzf nvim jq"'
```

## Limits

A container cannot show everything. Clipboard integration, a rootless Docker
service surviving a real logout, and how the configuration feels over days of
use are all outside its reach. See [Testing][testing] for the full list of
manual boundaries.

[docker]: https://www.docker.com/
[install-sh]: ../src/install.sh
[readme]: ../README.md
[shell-zsh]: ../src/dotfiles/shell.zsh
[testing]: testing.md
