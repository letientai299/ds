# Try ds in Docker

## New container

The [README][readme-try] downloads the [source installer][installer] and
starts a disposable [Docker][docker] container. The current directory is
mounted at `/work`. `--shell` applies `core` and opens Zsh. `exit` removes
the container; installed tools stay inside it.

Use `--no-apply` in place of `--shell` to preview without installing the
layer's tools.

Replace `ubuntu:24.04` with `alpine:3.21`, `fedora:latest`, or
`quay.io/centos/centos:stream10`.

## Existing container

Run the [existing-container snippet][readme-existing] inside a running
container. The install persists with that container.

## Inspect

```sh
ds status
ds status --verbose
ls -l ~/.config/ds
cat ~/.zshrc
command -v rg fzf nvim jq
```

`ds status` reports health and conflicts. The managed `.zshrc` block loads the
shell configuration. Open Neovim with `vi` to inspect its linked configuration.
Preview another apply with `ds apply core --dry-run`; use `ds remove core` to
remove managed links and blocks.

`remote` adds Tmux, Docker, and Yazi to core. Replace `--shell` with
`--layer remote --skip docker --shell`. A container without an engine cannot
pass the Docker readiness check.

For a trial that captures uncommitted source changes, use the checkout
workflows in [Architecture][architecture]. Those include `ds shell --docker`
and `mise run try`.

A container does not show clipboard integration or a rootless Docker service
surviving logout. Files created in bind-mounted directories may be owned by
root on a Linux host. See [Testing][testing] for manual checks.

[architecture]: architecture.md#working-from-a-checkout
[docker]: https://www.docker.com/
[installer]: ../scripts/install.sh
[readme-existing]: ../README.md#install-in-an-existing-container
[readme-try]: ../README.md#try-in-a-new-container
[testing]: testing.md
