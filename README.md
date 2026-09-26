# ds

`ds` manages my dotfiles, organize tools by layers, supports mac/ubuntu desktop,
remote machines and typical glibc containers, thus, enable me to reuse my
configuration in various environments.

> [!WARNING] This is for my personal use only. No support or promises.

## Install

### Try in a new container

```sh
curl -fsSLo /tmp/ds-install.sh \
  https://raw.githubusercontent.com/letientai299/ds/main/scripts/install.sh
docker run --rm -it \
  -v /tmp/ds-install.sh:/install.sh:ro \
  -v "$PWD":/work \
  -w /work \
  ubuntu:24.04 sh /install.sh --shell
```

### Install in an existing container

```sh
curl -fsSLo /tmp/ds-install.sh \
  https://raw.githubusercontent.com/letientai299/ds/main/scripts/install.sh
sh /tmp/ds-install.sh --shell
```

### Install on a host

```sh
curl -fsSLo ds-install.sh \
  https://raw.githubusercontent.com/letientai299/ds/main/scripts/install.sh
sh ds-install.sh --no-apply
sh ds-install.sh
```

## Update

```sh
ds update
ds apply
```

`ds update` pulls the tracked branches of `ds` and its installed configuration
sources: `nvim.conf`, `tmux.conf`, and `kitty.conf`. It honors `DS_NVIM_SOURCE`,
`DS_TMUX_SOURCE`, and `DS_KITTY_SOURCE`; otherwise it uses sibling checkouts.
Missing sibling checkouts are skipped. Every checkout must be clean and have an
upstream. Pulls use fast-forward only, with `ds` updated last. A failed pull stops
the command; earlier successful pulls remain applied.

Installed tool versions are unchanged. Delivered snapshots require a new
deployment.

## Documentation

See [docs][docs].

## License

[MIT][license]. Runtime notices are in [Third-party notices][third-party].

[docs]: docs/
[license]: LICENSE
[third-party]: src/THIRD-PARTY.md
