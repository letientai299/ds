# Command reference

Run commands through `./ds` in a controller checkout or through the installed
`~/.local/bin/ds` link.

Delivery and demo entrypoints are separate scripts rather than subcommands,
because they run before `ds` exists on the machine: `src/install.sh` and
`src/try.sh` are documented in [Gitless delivery][delivery] and
[Try ds in Docker][try].

| Command                                                    | Purpose                                                 |
| ---------------------------------------------------------- | ------------------------------------------------------- |
| `ds help`                                                  | Print the command list, layers, and optional components |
| `ds status LAYER`                                          | Report component and managed-file state                 |
| `ds diff LAYER`                                            | Show missing, conflicting, and unavailable entries      |
| `ds doctor [LAYER]`                                        | Show status plus Docker diagnostics for `remote`        |
| `ds apply LAYER [--dry-run] [--skip COMPONENT]`            | Converge a layer or preview it                          |
| `ds adopt LAYER [--dry-run]`                               | Back up conflicts, then converge                        |
| `ds force LAYER [--dry-run]`                               | Destructively replace conflicts, then converge          |
| `ds add COMPONENT [--dry-run]`                             | Enable an optional component                            |
| `ds unapply LAYER_OR_COMPONENT`                            | Remove exact managed state or an optional selection     |
| `ds shell`                                                 | Start an interactive Zsh with the current environment   |
| `ds shell-init`                                            | Print the Zsh integration fragment                      |
| `ds push HOST LAYER [OPTIONS]`                             | Deliver and apply from a controller checkout            |
| `ds docker-rootful --approve-rootful --grant-docker-group` | Explicitly provision rootful Docker                     |

`LAYER` is `core` or `remote`. The currently supported optional component is
`starship`. `ds help`, `ds --help`, and `ds -h` print the same list from the
catalog and exit successfully; an unrecognized layer or component name is
rejected before any state changes.

`--skip` accepts only `docker`, the one component `ds` converges outside
`mise bootstrap`. `adopt` and `force` reject it.

## Conflict operations

Normal `apply` stops before managed-file changes if a target conflicts.

`adopt` moves each conflict to `<target>.ds-adopted`, applies the managed
version, and lets `unapply` restore the original. Adoption fails rather than
overwrite an existing backup.

`force` removes conflicts recursively and creates no backup. Its dry-run lists
the targets that would be replaced.

Marked blocks in `.zshrc` and `.gitconfig` are the exception, because those
files belong to the user and `ds` only ever appends a block to them. When such a
block conflicts, `adopt` and `force` rewrite only the region between the
markers, including a block whose end marker was lost to a hand edit, and leave
the rest of the file untouched. `adopt` copies the file to `<target>.ds-adopted`
first. That copy is left for you to reconcile: `unapply` restores a
`.ds-adopted` backup only once the target itself is gone, which does not happen
while the rc file still holds content of your own.

## Controller push options

```text
ds push HOST LAYER \
  [--platform PLATFORM] \
  [--prefix RELATIVE_PATH] \
  [--home RELATIVE_PATH] \
  [--dry-run | --deliver-only]
```

- `--platform` overrides the SSH platform probe. Supported values are
  `macos-arm64`, `macos-x64`, `linux-arm64-musl`, and `linux-x64-musl`.
- `--prefix` changes the content-addressed installation root relative to the
  remote home. The default is `.local/share/ds`.
- `--home` applies inside an isolated relative home beneath the remote home.
- `--dry-run` delivers the snapshot and previews its layer application.
- `--deliver-only` installs the versioned snapshot without applying a layer.

Push is available only from a controller checkout because delivered snapshots do
not contain the controller transport scripts.

## Rootful Docker boundary

The rootful command requires both approval flags exactly as shown. Docker-group
membership is root-equivalent access, so normal `remote` apply never grants it
implicitly.

[delivery]: delivery.md
[try]: try.md
