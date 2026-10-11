# Getting started and recovery

ds supports macOS and glibc Linux on amd64 and arm64. musl hosts such as Alpine
are rejected before any change.

## From a checkout

Use a checkout on machines where you edit ds. Install [mise][mise] (and
[Homebrew][brew] on macOS), or provision with the bootstrap first, then clone
ds:

```sh
git clone https://github.com/letientai299/ds ~/dev/mine/ds
cd ~/dev/mine/ds
./ds add -l core -l extra -l ui --dry-run
./ds add -l core -l extra -l ui
```

The first `./ds` run trusts the checkout in mise and installs its Go. After a
bootstrap, switching to the checkout reuses the installed mise, tools, and
Neovim plugins; only links move. Clone `nvim.conf`, `tmux.conf`, or `kitty.conf`
next to ds, or set `sources` in `<config>/ds/config.toml`, to edit them live;
until then ds keeps the main build's snapshot of each and notes it in the plan.

ds links `~/.local/bin/ds` to the launcher and every managed file to the working
tree, so later commands run as `ds` and edits are live:

- Shell, Git, and tool files under `assets/` take effect in the next shell, or
  after `exec zsh`.
- Go changes rebuild on the next `ds` run.
- Catalog changes, such as new links or tools, apply on the next `ds add`.
- Links follow the checkout that last ran `add`; running `./ds add` from another
  worktree moves them there.

`ds upgrade` fast-forwards the checkouts instead of downloading a build;
snapshots stay at the installed build.

## Ubuntu or another host

```sh
sh -c "$(curl -fsSL https://letientai.io/ds/bootstrap.sh)" -- -l core -l extra
```

Run it interactively when packages are missing so sudo can prompt; automation
needs root or passwordless sudo. Hosts provisioned elsewhere can pass
`--no-packages` once Git, curl, Zsh, and Tmux exist.

## Remote hosts and job homes

```sh
ds deploy my-host -l core -l extra
ds deploy my-host --home /scratch/local/me/job/home -l core -l extra
ds --home /scratch/local/me/job/home add -l core -l extra
```

A selected home keeps its own builds, selection, and configuration. Container
runtimes, credentials, and host provisioning stay with the tools that own them.
Host-specific shell additions belong in `<config>/ds/local.zsh`.

## Recovery

- `ds status --verbose` lists every component and managed path.
- A conflict blocks the plan. Inspect the path, then rerun with `--force` to
  move it to `<state>/ds/backups/<time>/` and continue.
- A failed run prints the failed action and its operation record under
  `<state>/ds/operations/`. Fix the cause and rerun the same command.
- Remove a managed block by deleting the lines between its markers; ds adds it
  again on the next `add`.
- mise pins in `<config>/mise/config.toml` override ds defaults; edit that file
  rather than `conf.d/10-ds.toml`, which ds owns.

## Moving from the Janet version

Older installs used the same rc markers and linked into the old checkout or the
installer's `<data>/ds-source` clone. ds recognizes those blocks and links as
owned and replaces them. Other content at managed paths is a conflict. Old
`ds/layer`, `ds/components`, and `ds/mise` files are ignored; the first `add`
records the new selection. Environments that still export
`MISE_CONFIG_DIR=<config>/ds/mise` or a `MISE_ENV` with `core` or `remote` hide
the new tools; `ds status` notes the old directory. Unset both, then remove
`ds-source` and `ds/mise` once nothing else reads them. ds no longer provisions
Docker; existing runtimes stay untouched, and the shell keeps Docker aliases and
`serve`.

[brew]: https://brew.sh/
[mise]: https://mise.jdx.dev/getting-started.html
