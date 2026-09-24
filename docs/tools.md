# Shell tools

`ds apply core` installs `serve`, `fzf-files`, and `fzf-dirs` in `~/.local/bin` and
manages zoxide through mise. `extra` supplies gokill and Worktrunk. Trial shells expose the same commands. Existing files at
managed paths follow the normal adoption and conflict rules.

## File selection and search

FZF and Ctrl+T use `fzf-files`, with hidden files enabled and normal ignore
rules preserved. The [include settings][fzf-includes] add `.ai`, `.dump`, and
root-local configuration files even when ignored. Extra scans stay within those
explicit directories. The helper runs only when invoked and removes duplicates.

Ripgrep uses the managed [rgrc][rgrc] for case-insensitive searching. Pass `-s`
to match case for one invocation. The [shell exports][exports] also select
Neovim as the editor and configure history. The UTF-8 locale uses `en_US.UTF-8`
on macOS and `C.UTF-8` on Linux. Local overrides belong in
`$XDG_CONFIG_HOME/ds/local.zsh`.

## Navigate directories and worktrees

Use `z` and `zi` for [zoxide][zoxide] navigation across projects. Use `j query`
to jump to a remembered directory inside the current Git checkout. With no
match, or no query, `j` opens the scoped `fzf-dirs` picker. Outside Git, the
picker stays under the current directory. Ignored directory searches use the
same bounded include settings as file selection.

[Worktrunk][worktrunk] is available as `wt` in `extra`. Its upstream shell
integration loads after completion initializes, or on the first invocation,
so `wt switch` can change the current shell's directory. ds owns this integration;
there is no need to run `wt config shell install`. Use native Git commands
alongside Worktrunk; the old Git automation scripts are not included.

No terminal file manager is selected by ds. Existing independently installed
file managers are left under their current package manager's ownership.

## Completion and shell conveniences

[zsh-completions][completions] joins the existing deferred completion setup.
`~/.local/share/zsh/site-functions` and the corresponding XDG data path accept
personal completion definitions. SSH completion combines config aliases with
known hosts, follows user config includes, and re-reads them when completing.
It skips include cycles and bounds config traversal. It does not scan SSH files
at startup or on each prompt.

`local_todo` opens `.dump/todo.md` in `$EDITOR`, shared by a repository's
worktrees. `so` sources a file, `:q` exits, and `wrap` / `nowrap` control terminal
line wrapping. Interactive comments are enabled, the bell is disabled, and
Ctrl-D does not exit the shell. `exit` and `:q` still exit normally.

`gon` retains its existing `git open` alias. The separate `git-open` dependency
must already be available if this alias is used.

## Automatic project environments

To enable mise's interactive environment activation, add this to
`$XDG_CONFIG_HOME/ds/local.zsh` and start a new shell:

```zsh
export DS_MISE_ACTIVATE=1
```

Activation runs before the first command and installs directory/prompt hooks.
This makes project variables available in the shell itself. It is deliberately
not deferred, since that could leave early commands with the wrong environment.
Repeated sourcing does not install duplicate hooks. Without this option, ds
uses shims; `mise exec` and `mise run` still load project environments explicitly.

## Serve a directory

```sh
serve ./dist
serve -p 3000 ./public
serve --no-live --no-open ./dist
```

`serve` uses [Caddy][caddy] in Docker and opens the default browser. Docker must
already be running. Live reload works on a temporary copy, leaving source files
unchanged. `--no-live` serves the source directory through a read-only mount;
`--no-open` leaves browser navigation to the caller. Ctrl+C stops the container
and removes temporary files.

Native filesystem watchers are used when available. Otherwise, content polling
detects edits, additions, renames, and deletions. Polling reads the served files
each second, so use a build-output directory rather than a large checkout.

## Select processes to stop

```sh
gokill
gokill node
gokill 3000
```

[gokill][gokill] provides process discovery, fuzzy selection, and signaling.
Queries match process names, PIDs, users, and ports. `/` edits
the filter; Enter leaves filtering, then Enter sends TERM to the selected
process. Ctrl+R refreshes, `i` shows details, `T` opens the dependency tree, `P`
shows listening processes, and Ctrl+C quits.

The picker lists all users and signals one selected PID. Tree browsing does
not imply recursive killing. Multi-selection and custom signals are unsupported.
For a different signal, use the PID shown in the picker with `kill`.

Mise manages gokill as the `http:gokill` tool. Its version and platform
checksums are pinned in the [extra profile][profile]; `ds apply extra`
installs it. Neither command adds work to shell startup.

[caddy]: https://caddyserver.com/docs/caddyfile/directives/file_server
[gokill]: https://github.com/w31r4/gokill
[profile]: ../src/mise/mise.extra.toml
[fzf-includes]: ../src/dotfiles/fzf-includes.zsh
[rgrc]: ../src/dotfiles/rgrc
[exports]: ../src/dotfiles/exports.zsh
[worktrunk]: https://worktrunk.dev/
[zoxide]: https://github.com/ajeetdsouza/zoxide
[completions]: https://github.com/zsh-users/zsh-completions

## Kitty

`ds apply ui` installs Kitty through mise and provides `kt`, which launches the
[custom Kitty repository][kitty-config] with its own configuration and helpers.
The `ui` layer is independent; apply `core` too for the fzf and Neovim features
used by that configuration, or apply `all` for every layer.

Kitty supports macOS and Linux with glibc 2.35 or newer. `ui` and `all` reject
Alpine and older glibc hosts before installation. A display is required to open
a window. Ubuntu ARM64 CLI startup is verified; Rocky 9's older glibc cannot
run the pinned upstream package.

A source checkout uses the sibling `kitty.conf` checkout or `DS_KITTY_SOURCE`.
Build its launcher with that repository's build task before `ds apply ui`;
`mise run install -- --layer ui` also builds it. Delivered snapshots contain
compiled helpers and configuration, so destination hosts do not need Go.
The `kt` launcher preserves the repository's per-instance configuration; ds does
not register desktop shortcuts or change existing Kitty windows.

[kitty-config]: https://github.com/letientai299/kitty.conf
