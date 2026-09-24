# Shell tools

`ds apply core` installs `serve` and `fkill` in `~/.local/bin`. Trial shells
expose the same commands through their isolated bin directory. Existing files
at the installed paths follow the normal adoption and conflict rules.

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
fkill
fkill node
fkill 3000
```

`fkill` delegates process discovery, fuzzy selection, and signaling to
[gokill][gokill]. Queries match process names, PIDs, users, and ports. `/` edits
the filter; Enter leaves filtering, then Enter sends TERM to the selected
process. Ctrl+R refreshes, `i` shows details, `T` opens the dependency tree, `P`
shows listening processes, and Ctrl+C quits.

The picker lists all users and signals one selected PID. Tree browsing does
not imply recursive killing. The old multi-selection, recursive tree killing,
`-a`, `-9`, and `-s` options are not retained; unsupported flags fail explicitly.
For a different signal, use the PID shown in the picker with `kill`.

Mise manages gokill as the `http:gokill` tool. Its version and platform
checksums are pinned in the [core profile][profile]; `ds apply core`
installs it. The wrapper calls that mise-managed executable directly, avoiding
unrelated tools on PATH. Neither command adds work to shell startup.

[caddy]: https://caddyserver.com/docs/caddyfile/directives/file_server
[gokill]: https://github.com/w31r4/gokill
[profile]: ../src/mise/mise.toml
