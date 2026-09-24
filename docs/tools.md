# Shell tools

`ds apply core` installs `serve` in `~/.local/bin` and manages gokill through
mise. Trial shells expose both commands. Existing files at the managed `serve`
path follow the normal adoption and conflict rules.

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
checksums are pinned in the [core profile][profile]; `ds apply core`
installs it. Neither command adds work to shell startup.

[caddy]: https://caddyserver.com/docs/caddyfile/directives/file_server
[gokill]: https://github.com/w31r4/gokill
[profile]: ../src/mise/mise.toml
