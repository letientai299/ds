# Try ds in Docker

`src/try.sh` builds a snapshot, applies a layer inside a throwaway
[container][docker], and hands over an interactive login Zsh. Nothing touches
your own home, and the container disappears on exit.

## Without a checkout

```sh
curl -fsSL https://raw.githubusercontent.com/letientai299/ds/main/src/try.sh | sh
```

The container installs the latest release with
[`src/install.sh`](../src/install.sh), applies `core`, then opens Zsh. Only
Docker is needed on the host.

## From a checkout

```sh
mise run try
```

This packs the working tree into a snapshot instead of downloading a release, so
it reflects uncommitted changes. It needs the pinned runtimes; see the working
notes in the [README](../README.md). Force either payload source explicitly:

```sh
./src/try.sh --source checkout
./src/try.sh --source release --version v1.0.0
```

## What to look at

Once the prompt appears, the container is a normal target: the managed `.zshrc`
marker has loaded [`src/dotfiles/shell.zsh`](../src/dotfiles/shell.zsh), and
every layer component is on `PATH`.

```sh
ds status core        # component and managed-file state
ds doctor core        # status plus diagnostics
ls -l ~/.config/ds    # the dedicated files ds owns
cat ~/.zshrc          # the marker block ds inserted
```

The prompt, history behaviour, aliases, and the `n` wrapper for `nnn` are the
daily-driver surface. Open Neovim with `vi` to see the linked configuration, and
try `fzf`, `rg`, `fd`, and `jq` directly.

Preview commands answer the question that matters before adopting `ds` on a real
machine — what would it change?

```sh
ds diff core
ds apply core --dry-run
ds unapply core       # remove everything ds owns, then look around again
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
use are all outside its reach. See [Testing](testing.md) for the full list of
manual boundaries.

[docker]: https://www.docker.com/
