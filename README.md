# ds

`ds` installs a layered shell and tool setup on macOS and Linux. The [source
installer][installer] runs directly from GitHub; you do not need a checkout or a
published release.

## Try in Docker

Download the installer, then run it in a disposable [Docker][docker] container:

```sh
curl -fsSLo /tmp/ds-install.sh \
  https://raw.githubusercontent.com/letientai299/ds/main/scripts/install.sh
docker run --rm -it -v /tmp/ds-install.sh:/install.sh:ro \
  ubuntu:24.04 sh /install.sh --shell
```

The installer clones `main`, applies the `core` layer, and opens Zsh. Run
`ds status` or `ds help` inside the container. `exit` removes the container; the
installed tools and configuration stay inside it. Use `--no-apply` in place of
`--shell` to preview changes without installing the layer's tools.

The same installer works with `alpine:3.21`, `fedora:latest`, and
`quay.io/centos/centos:stream10` in place of `ubuntu:24.04`. See [Trying
ds][try] for commands to inspect the result.

## Install on a machine

Download and inspect the [installer][installer], then run it:

```sh
curl -fsSLo ds-install.sh \
  https://raw.githubusercontent.com/letientai299/ds/main/scripts/install.sh
sh ds-install.sh --no-apply
sh ds-install.sh
```

The preview installs prerequisites and runtimes, then shows the changes to
`core`. The final command applies `core`. Run `sh ds-install.sh --shell` to open
Zsh after applying. The launcher is available at `~/.local/bin/ds`.

The installer supports macOS, Ubuntu, Debian, Alpine, Fedora, and CentOS Stream
on supported ARM64 and x64 hosts. Linux package installation needs root or
`sudo`. On macOS, install Command Line Tools and [Homebrew][brew] first. Sources
are cloned under `${XDG_DATA_HOME:-~/.local/share}/ds-source`; keep them because
managed files link to them. An existing checkout in that location is reused
without pulling or resetting it. Run `sh ds-install.sh --help` for options such
as `--layer`, `--prefix`, and `--skip docker`.

Normal apply refuses conflicting targets. Preview a backup and replacement
before allowing it:

```sh
~/.local/bin/ds apply core --force --dry-run
~/.local/bin/ds apply core --force
```

`--force` backs up conflicting files to `<target>.ds-adopted`; managed blocks
in shell and Git startup files are updated in place. See [Getting started and
recovery][getting-started] for ownership and removal.

## Layers

`core` is the daily setup. `remote` extends it; `extra` and `ui` are
independent, and `all` selects every layer. Run `ds help` for component lists or
`ds status LAYER --verbose` for resolved files. SSH delivery and other workflows
that use a checkout are in [Architecture][architecture].

## Documentation

- [Trying ds][try]
- [Getting started and recovery][getting-started]
- [Command reference][cli]
- [Architecture and checkout workflows][architecture]
- [Gitless delivery][delivery]
- [Testing][testing]

## License

[MIT][license]. Runtime notices are in [Third-party notices][third-party].

[architecture]: docs/architecture.md
[brew]: https://brew.sh/
[cli]: docs/cli.md
[delivery]: docs/delivery.md
[docker]: https://www.docker.com/
[getting-started]: docs/getting-started.md
[installer]: scripts/install.sh
[license]: LICENSE
[testing]: docs/testing.md
[third-party]: src/THIRD-PARTY.md
[try]: docs/try.md
