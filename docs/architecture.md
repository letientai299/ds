# Architecture

ds is one Go CLI. The [entrypoint][main] stays thin, [`internal/cli`][cli] maps
[Cobra][cobra] commands onto domain operations in [`internal/ds`][ds], and
[`internal/assets`][assets] reads ds assets from a checkout or from the snapshot
embedded in a main build. Configuration repositories are Git checkouts on the
target. CI tooling lives in [`internal/build`][build].

## Execution modes

| Mode       | ds assets                             | `upgrade ds`                                            |
| ---------- | ------------------------------------- | ------------------------------------------------------- |
| Checkout   | Live files in the checkout            | Sync sources, rebuild, resume                           |
| Main build | Snapshot compiled into the executable | Sync sources, fetch and verify the latest build, resume |

The build selects the mode, never the working directory. The checkout launcher
compiles with the checkout root linked in; main builds compile with the
`dsembed` tag and the snapshot. An installed main binary run inside a checkout
stays in main mode.

## Configuration repositories

`nvim.conf`, `tmux.conf`, and `kitty.conf` stay separate repositories. ds clones
one on first use, from the URL in the [catalog][catalog], when a selected
component links into it. The first match places each repository:

1. `sources.<repo>` in `<config>/ds/config.toml`.
2. In checkout mode, a sibling of the ds checkout.
3. In main mode, a shallow clone under `<data>/ds/sources`.

```toml
[sources]
nvim = "~/src/nvim.conf"
```

The first two belong to the user; `upgrade ds` preserves their edits.
Clones under `<data>/ds/sources` belong to ds: `upgrade ds` resets them to the
remote head and discards local edits. Edit configuration in a user checkout
instead. See [upgrade categories][upgrades] for synchronization and recovery.

Helpers such as `kt` build inside their repository with its pinned Go through
`mise exec go`, so hosts that select Kitty install Go but no other tools of that
repository.

## Convergence

```mermaid
flowchart LR
  Input[Selection and target] --> Inspect[Inspect host and owned files]
  Inspect --> Plan[Build action plan]
  Assets[Live or embedded assets] --> Plan
  Plan --> Preview[Render dry run]
  Plan --> Execute[Execute actions]
  Execute --> Record[Record progress and selection]
  Record --> Activate[Activate successful main build]
```

One plan serves both preview and execution. Planning inspects the host and the
target's files and records blockers: conflicts without `--force`, missing
sources, unsupported platforms, and missing privileges or package managers. A
blocked plan never executes. Actions are concrete types, not shell snippets, and
every external command receives an argument array.

Actions run in this order: stage the main build, fetch mise when no compatible
one exists, install native packages, clone missing configuration repositories,
build helpers, converge files, activate the main build, install mise tools, and
bootstrap Neovim plugins. Activation precedes tool installation because ds asset
links resolve through the activated build.

Execution rechecks each file's state before changing it and stops if the file
changed since planning. Each run writes an operation record under
`<state>/ds/operations`; a failure names the failed action, and a rerun
converges from observed state. Package installs, downloads, and file edits are
not one transaction.

## Ownership

| Kind           | Owned when                                                     |
| -------------- | -------------------------------------------------------------- |
| Symlink        | It points at the desired asset, a recorded source, or ds roots |
| Rc block       | Content sits between `# >>> ds managed >>>` markers            |
| Generated file | Its digest matches what ds last wrote                          |

ds replaces only owned content. Anything else is a conflict that `--force` moves
to `<state>/ds/backups/<time>`. Blocks preserve content around them, and ds
never edits a symlinked rc file. `<state>/ds/state.json` stores the selection
and ownership records. An advisory lock on `<state>/ds/lock` serializes
mutations of one target; the process holding it can pass it to the next ds
during an upgrade.

## Tools and packages

ds writes tool requests to `<config>/mise/conf.d/10-ds.toml`. mise loads
`conf.d` fragments before `config.toml`, so user declarations override ds
defaults; see [mise configuration][mise-config]. ds installs and inspects only
the tools of selected components, outside any project configuration.

Native packages install through [mise's package bootstrap][mise-bootstrap] with
Homebrew on macOS and apt on Ubuntu, only when a component's commands are
missing. When no compatible mise exists, ds downloads a pinned release, verifies
its checksum, and links it into `~/.local/bin`.

## Main build layout

A main build stages under `<data>/ds/builds/<build-id>`: the executable,
`assets/ds/`, and `build.json`, written last to mark completion.
`<data>/ds/current` points at the active build; `~/.local/bin/ds` and every ds
asset link resolve through it. Activation is a same-directory symlink rename. ds
keeps the active and previous builds and removes older ones.

[assets]: ../internal/assets
[build]: ../internal/build
[catalog]: ../assets/catalog.toml
[cli]: ../internal/cli
[cobra]: https://github.com/spf13/cobra
[ds]: ../internal/ds
[main]: ../cmd/ds/main.go
[mise-bootstrap]: https://mise.jdx.dev/cli/bootstrap.html
[mise-config]: https://mise.jdx.dev/configuration.html
[upgrades]: cli.md#upgrade-categories
