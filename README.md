# ds

`ds` configures my development environment on macOS and Ubuntu, locally or over
SSH. It converges selected layers and components of tooling and configuration in
a home directory. [mise][mise] installs tools; the host package manager supplies
native prerequisites; Zsh and Lua configuration stay as they are.

> [!WARNING] This is for my personal use only. No support or promises.

## Install the latest main build

```sh
sh -c "$(curl -fsSL https://letientai.io/ds/bootstrap.sh)" -- -l core -l extra
```

The bootstrap downloads the binary for this host, verifies its SHA-256, and runs
`ds add` with the given selectors, or `-l core` without any. It needs `curl` or
`wget` and a SHA-256 tool; no Go, Git, or checkout.

## Run from a checkout

```sh
git clone https://github.com/letientai299/ds
cd ds
./ds add -l core -l extra -l ui --dry-run
./ds add -l core -l extra -l ui
```

The `./ds` launcher trusts the checkout in mise, installs its Go on first use,
builds the CLI, and reads live assets, including uncommitted edits. Sibling
`nvim.conf`, `tmux.conf`, and `kitty.conf` checkouts supply editor, Tmux, and
Kitty configuration; without one, ds keeps the installed main build's snapshot.

## Everyday commands

```sh
ds                          # status of the saved selection
ds add tmux yazi            # add components
ds add -l extra             # add a layer
ds status --check           # exit 1 unless complete
ds upgrade                  # ds, tools, plugins, and system packages
ds deploy my-host -l core   # install on an SSH host
ds shell                    # trial shell with isolated configuration
```

See the [documentation][docs].

## License

[MIT][license]. Notices for vendored shell code are in [third-party
notices][third-party].

[docs]: docs/README.md
[license]: LICENSE
[mise]: https://mise.jdx.dev/
[third-party]: assets/THIRD-PARTY.md
