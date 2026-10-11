# Shell tools

The `zsh` component links `serve`, `fzf-files`, and `fzf-dirs` into `~/.local/bin`; zoxide
comes through mise. `extra` supplies eza and Worktrunk. Trial shells expose the
same commands. Existing files at managed paths follow the normal ownership and
conflict rules.

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
integration loads after completion initializes, or on the first invocation, so
`wt switch` can change the current shell's directory. ds owns this integration;
there is no need to run `wt config shell install`. Use native Git commands
alongside Worktrunk; the old Git automation scripts are not included.

The `core` layer installs [Yazi][yazi]. Run `r` to open it and keep its final
directory in the shell after quitting. Its managed configuration lives under
`$XDG_CONFIG_HOME/ds/yazi`, leaving a personal `~/.config/yazi` independent.

## Completion and shell conveniences

[zsh-completions][completions] joins the existing deferred completion setup. Tab
completion tries exact case first, then matches case insensitively. It also
works with the cursor inside a word. History expansions return to the command
line for review before execution. `~/.local/share/zsh/site-functions` and the
corresponding XDG data path accept personal completion definitions. SSH
completion combines config aliases with known hosts, follows user config
includes, and re-reads them when completing. It skips include cycles and bounds
config traversal. It does not scan SSH files at startup or on each prompt.

`local_todo` opens `.dump/todo.md` in `$EDITOR`, shared by a repository's
worktrees. `so` sources a file, `:q` exits, and `wrap` / `nowrap` control
terminal line wrapping. Interactive comments are enabled, the bell is disabled,
and Ctrl-D does not exit the shell. `exit` and `:q` still exit normally.

`gon` runs `git open`; the `git` component installs `git-open` through mise.

## Automatic project environments

To enable mise's interactive environment activation, add this to
`$XDG_CONFIG_HOME/ds/local.zsh` and start a new shell:

```zsh
export DS_MISE_ACTIVATE=1
```

Activation runs before the first command and installs directory/prompt hooks.
This makes project variables available in the shell itself. It is deliberately
not deferred, since that could leave early commands with the wrong environment.
Repeated sourcing does not install duplicate hooks. Without this option, ds uses
shims; `mise exec` and `mise run` still load project environments explicitly.

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

## Disk usage and archives

`ds add -l extra` installs [gdu][gdu] for disk usage analysis and [ouch][ouch]
for creating, listing, and extracting archives.

```sh
gdu .
ouch compress ./logs logs.tar.zst
ouch list logs.tar.zst
ouch decompress logs.tar.zst --dir restored
```

Ouch supports ZIP, TAR, 7z, gzip, bzip2, xz, zstd, and other compression
formats. RAR supports extraction and listing only.

[caddy]: https://caddyserver.com/docs/caddyfile/directives/file_server
[gdu]: https://github.com/dundee/gdu
[ouch]: https://github.com/ouch-org/ouch
[fzf-includes]: ../assets/dotfiles/fzf-includes.zsh
[rgrc]: ../assets/dotfiles/rgrc
[exports]: ../assets/dotfiles/exports.zsh
[worktrunk]: https://worktrunk.dev/
[zoxide]: https://github.com/ajeetdsouza/zoxide
[completions]: https://github.com/zsh-users/zsh-completions
[yazi]: https://yazi-rs.github.io/

## Kitty

`ds add -l ui` installs Kitty through mise and provides `kt`, which launches Kitty
with the configuration and helpers from [`kitty.conf`][kitty-conf]. The `ui`
layer is independent; add `core` too for the fzf and Neovim features used by
that configuration.

Kitty supports macOS and Linux with glibc 2.35 or newer. Plans that select it on
older glibc hosts block before installation. A display is required to
open a window. Ubuntu ARM64 CLI startup is verified; Rocky 9's older glibc
cannot run the pinned upstream package.

A checkout uses the sibling `kitty.conf`, `sources.kitty` in
`<config>/ds/config.toml`, or the installed main build's snapshot, and builds the helper with that repository's Go
toolchain when it is missing or older than its sources. Main builds embed the
compiled helper, so destination hosts do not need Go. The `kt` launcher
preserves the repository's per-instance configuration; ds does not register
desktop shortcuts or change existing Kitty windows.

[kitty-conf]: https://github.com/letientai299/kitty.conf
