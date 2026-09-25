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

## Documentation

See [docs][docs].

## License

[MIT][license]. Runtime notices are in [Third-party notices][third-party].

[docs]: docs/
[license]: LICENSE
[third-party]: src/THIRD-PARTY.md
