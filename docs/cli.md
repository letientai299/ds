# Command reference

Run commands through `./ds` in a controller checkout or through the installed
`~/.local/bin/ds` link.

Delivery and demo entrypoints are separate scripts rather than subcommands,
because they run before `ds` exists on the machine: `src/install.sh` and
`src/try.sh` are documented in [Gitless delivery][delivery] and
[Try ds in Docker][try].

The primary commands follow the daily workflow:

| Command              | Purpose                                            |
| -------------------- | -------------------------------------------------- |
| `ds` or `ds shell`   | Open the persistent trial shell                    |
| `ds shell --docker`  | Open cached Ubuntu; checkout only                  |
| `ds apply [TARGET]`  | Apply a layer or enable an optional component      |
| `ds status [TARGET]` | Summarize health and list problems                 |
| `ds remove TARGET`   | Remove managed configuration or optional selection |
| `ds push HOST LAYER` | Deliver and apply over SSH; checkout only          |

`ds help` lists components by layer from the generated catalog.

`TARGET` accepts a catalog layer or optional component. Omitted targets use the
saved layer, initially `core`. An invalid saved layer fails explicitly. Removal
requires a target and leaves packages installed. The `remote` layer is an
extended local preset; only `push` selects an SSH destination.

Status, application, and removal identify the layer and configuration scope.
Inside `ds shell`, configuration changes use the persistent trial directory;
package installation still affects the host. `ds status --verbose` includes
healthy entries and Docker diagnostics. The default report suggests a preview
command when changes are needed. `ds apply --dry-run` shows the full action plan.

`ds help`, `ds --help`, and `ds -h` show primary commands and examples.
`ds help --all` also shows delivery (`stage`, `activate`, `rollback`), integration
(`shell-init`, `completion`), and host provisioning (`docker-rootful`).
Rollback switches the active snapshot; it does not reverse package installation
or all prior file changes. Delivered snapshots omit unavailable controller
commands from help and completions.

Existing commands remain available:

| Existing command   | Preferred form               |
| ------------------ | ---------------------------- |
| `ds add COMPONENT` | `ds apply COMPONENT`         |
| `ds diff TARGET`   | `ds status TARGET`           |
| `ds doctor TARGET` | `ds status TARGET --verbose` |
| `ds docker`        | `ds shell --docker`          |

Legacy `diff` and `doctor` retain their output; bare `doctor` still defaults to
`core`. Shell completion offers primary commands first and includes advanced
commands when completing a typed prefix or `ds help`.

Commands accept `--help` before performing work. `ds help COMMAND` describes
command-specific options, effects, and an example. Unknown trailing arguments
are rejected. Mutation previews show package convergence, exact file paths,
backup destinations, selection changes, and activation from the same action
plan used for execution. A blocked plan explains what must be resolved first.

The managed shell loads completions automatically. For another interactive shell:

```sh
source <(ds completion zsh) # after compinit
# Bash: source <(ds completion bash)
```

The installed shell also provides [serve and gokill][tools].

## Status for automation

`ds status TARGET --json` emits one JSON object with `schema: 1`, `target`,
`summary`, `components`, `files`, and `selected`. `TARGET` can also be an optional
component. Component states are `installed`, `missing`, `outdated`, or
`unavailable`; managed-file states remain `present`, `missing`, `conflict`, or
`unavailable`.

For mise tools, `expected` is the version pinned by ds's selected profile,
`installed` lists healthy installed versions, and `executables` records the
selected version's executable paths. One cached filesystem inventory checks the
pinned executables, including archive subdirectories. An empty install directory
is not healthy. `outdated` means a different version is installed, even when it
is newer than the pin. Native tools are checked on PATH without querying a
package repository for newer versions. This is an installation-health check;
it does not execute each tool to prove runtime compatibility.

`--check` returns **0** when complete, **1** when incomplete or conflicting,
and **2** for invalid command arguments. Without `--check`, an unhealthy status
is still a successful report. Combine `--json --check` for automation.

Docker reports a separate `probe`: `ready`, `missing`, `missing-plugin`,
`unreachable`, or `timeout`. Each of `info`, Buildx, and Compose has a three-second
deadline, so a successful info probe followed by slow plugins is bounded by nine
seconds. Only one set of probes runs per invocation. Missing Docker is distinct
from a daemon that cannot be reached.

`apply --skip docker` skips Docker convergence for layer applications, including
the `--force` conflict policy. Optional-component applications reject
`--skip` and conflict policies.

## Conflict operations

Normal `apply` checks all managed-file conflicts and source availability before
package changes and reports the `--force --dry-run` preview command.

`apply --force` moves each conflict to `<target>.ds-adopted`, applies the managed
version, and lets `remove` restore the original. It checks every backup destination
first and refuses to overwrite an existing backup. `--adopt` remains a
compatibility alias for `--force`; both preserve backups.

Marked blocks in `.zshrc` and `.gitconfig` belong to files shared with the user.
For a conflicting block, `--force` copies the file to `<target>.ds-adopted`, then
rewrites only the region between the markers, including a block whose end marker
was lost to a hand edit. The rest of the file remains unchanged. That copy is left
for you to reconcile: `remove` restores a `.ds-adopted` backup only once the target
itself is gone, which does not happen while the rc file holds your own content.

## Controller push options

```text
ds push HOST LAYER \
  [--platform PLATFORM] \
  [--prefix RELATIVE_PATH] \
  [--home RELATIVE_PATH] \
  [--force] \
  [--dry-run | --deliver-only]
```

- `--platform` overrides the SSH platform probe. Supported values are
  `macos-arm64`, `macos-x64`, `linux-arm64-musl`, and `linux-x64-musl`.
- `--prefix` changes the content-addressed installation root relative to the
  remote home. The default is `.local/share/ds`.
- `--home` applies inside an isolated relative home beneath the remote home.
- `--force` backs up conflicting remote targets before applying. Combine it with
  `--dry-run` to preview. It cannot be combined with `--deliver-only`. The old
  `--adopt` spelling remains an alias.
- `--dry-run` delivers the snapshot and previews its layer application.
- `--deliver-only` stages the versioned snapshot without application or activation.
  `--dry-run` also leaves the active version unchanged.

Push is available only from a controller checkout because delivered snapshots do
not contain the controller transport scripts.

## Rootful Docker boundary

The rootful command requires both approval flags exactly as shown. Docker-group
membership is root-equivalent access, so normal `remote` apply never grants it
implicitly.

[delivery]: delivery.md
[try]: try.md
[tools]: tools.md
