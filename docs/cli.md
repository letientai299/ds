# Command reference

Run commands through `./ds` in a controller checkout or through the installed
`~/.local/bin/ds` link.

| Command                                                    | Purpose                                               |
| ---------------------------------------------------------- | ----------------------------------------------------- |
| `ds status LAYER`                                          | Report component and managed-file state               |
| `ds diff LAYER`                                            | Show missing, conflicting, and unavailable entries    |
| `ds doctor [LAYER]`                                        | Show status plus Docker diagnostics for `remote`      |
| `ds apply LAYER [--dry-run] [--skip COMPONENT]`            | Converge a layer or preview it                        |
| `ds adopt LAYER [--dry-run]`                               | Back up conflicts, then converge                      |
| `ds force LAYER [--dry-run]`                               | Destructively replace conflicts, then converge        |
| `ds add COMPONENT [--dry-run]`                             | Enable an optional component                          |
| `ds unapply LAYER_OR_COMPONENT`                            | Remove exact managed state or an optional selection   |
| `ds shell`                                                 | Start an interactive Zsh with the current environment |
| `ds shell-init`                                            | Print the Zsh integration fragment                    |
| `ds push HOST LAYER [OPTIONS]`                             | Deliver and apply from a controller checkout          |
| `ds docker-rootful --approve-rootful --grant-docker-group` | Explicitly provision rootful Docker                   |

`LAYER` is `core` or `remote`. The currently supported optional component is
`starship`.

## Conflict operations

Normal `apply` stops before managed-file changes if a target conflicts.

`adopt` moves each conflict to `<target>.df-adopted`, applies the managed
version, and lets `unapply` restore the original. Adoption fails rather than
overwrite an existing backup.

`force` removes conflicts recursively and creates no backup. Its dry-run lists
the targets that would be replaced.

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
  remote home. The default is `.local/share/df`.
- `--home` applies inside an isolated relative home beneath the remote home.
- `--dry-run` delivers the snapshot and previews its layer application.
- `--deliver-only` installs the versioned snapshot without applying a layer.

Push is available only from a controller checkout because delivered snapshots
do not contain the controller transport scripts.

## Rootful Docker boundary

The rootful command requires both approval flags exactly as shown. Docker-group
membership is root-equivalent access, so normal `remote` apply never grants it
implicitly.
