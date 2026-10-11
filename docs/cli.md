# Command reference

`ds --help` and `ds COMMAND --help` print the authoritative flags.

| Command                                        | Behavior                                              |
| ---------------------------------------------- | ----------------------------------------------------- |
| `ds`                                           | Show status for saved selection                       |
| `ds add COMPONENT...`                          | Add individually selected components                  |
| `ds add -l LAYER [-l LAYER]...`                | Add selected layers                                   |
| `ds status [COMPONENT...]`                     | Inspect saved selection or supplied components        |
| `ds status -l LAYER [-l LAYER]...`             | Inspect supplied layers                               |
| `ds shell`                                     | Enter a persistent isolated trial environment         |
| `ds deploy HOST [COMPONENT...]`                | Deploy through OpenSSH; default to `core`             |
| `ds deploy HOST -l LAYER [-l LAYER]...`        | Deploy specified layers                               |
| `ds upgrade [ds\|tools\|plugins\|system\|all]` | Upgrade requested categories; default to all          |
| `ds completion zsh\|bash`                      | Generate shell completion                             |
| `ds version [--json]`                          | Report mode, source/build commit, and asset revisions |

## Selectors

Positional arguments name components. `-l` or `--layer` names one layer per
occurrence; repeat it for several layers. One invocation uses either layers or
components, never both, so `ds add -l ui nvim` fails before any effect. A layer
name given positionally fails with a hint to use `--layer`. Run separate
invocations to add a layer and a component.

`add` takes the union with the saved selection, resolves dependencies, and
converges the result. Repeating an addition changes nothing. Neither `add` nor
`upgrade` uninstalls anything. A component added alone receives its declared
dependencies, such as mise and Git for Neovim, without the rest of a layer. New
members of a saved layer join on the next `add` or `upgrade`.

The [catalog][catalog] declares layers, components, tools, native packages,
dependencies, and owned files.

## Flags

- `--dry-run` (`add`, `deploy`, `upgrade`) prints the plan. A local preview
  writes nothing and reports facts it cannot resolve without effects.
- `--force` (`add`, `deploy`) backs up conflicting files, then replaces them.
  Backups go under `<state>/ds/backups` and are never overwritten.
- `--no-packages` (`add`, `deploy`) skips native packages; their commands must
  already exist. mise tools still install.
- `--home PATH` operates on another home. XDG and mise paths derive from it,
  ignoring inherited `XDG_*` and `MISE_*` variables. For `deploy`, the path is
  remote and relative paths resolve against the remote login home.
- `status --verbose` lists healthy items, `--json` prints a report to stdout,
  and `--check` exits 1 unless status is complete.
- `upgrade --skip CATEGORY` excludes a category, such as `system` on hosts
  provisioned elsewhere.

## Upgrade categories

- `ds` refreshes ds and its assets, then converges the saved selection. A
  checkout fast-forwards its clean, tracking source repositories and rebuilds. A
  main build fetches and verifies the latest published build.
- `tools` runs `mise upgrade` for tools of selected components. Explicit user
  requests in mise configuration stay authoritative.
- `plugins` updates Neovim plugins when Neovim is selected.
- `system` upgrades packages through Homebrew or apt.

Bare `upgrade` runs every category, `ds` first. Narrow categories do not pull
sources. A failed `ds` stage stops the rest; other failures are reported per
category.

## Privileges

ds never prompts for confirmation. Interactive runs that install Linux packages
authorize sudo first. Automation needs root or cached or passwordless sudo;
otherwise the plan blocks with a remedy. Homebrew is required on macOS and is
never installed implicitly. ds never changes the login shell.

## Output and exit status

JSON goes to stdout; progress and diagnostics go to stderr. Exit status is `0`
on success, `1` for a failed operation or an unhealthy `status --check`, and `2`
for invalid input. An unhealthy `status` without `--check` exits 0. Status reads
local and cached facts only.

[catalog]: ../assets/catalog.toml
