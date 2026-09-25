# Try ds in Docker

The [README][readme] shows how to download the [source installer][installer]
and run it in a disposable [Docker][docker] container without a checkout. Use
`--shell` to apply `core` and enter Zsh. `exit` removes the container.

Run these commands inside the container to inspect the result:

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

`remote` adds Tmux, Docker, and Yazi to core. To try it, replace `--shell` in
the README's Docker command with `--layer remote --skip docker --shell`.
A container without an engine cannot pass the Docker readiness check.

For a trial that captures uncommitted source changes, use the checkout workflows
in [Architecture][architecture]. Those include `ds shell --docker` and
`mise run try`.

A container does not show clipboard integration or a rootless Docker service
surviving logout. Files created in bind-mounted directories may be owned by
root on a Linux host. See [Testing][testing] for manual checks.

[architecture]: architecture.md#working-from-a-checkout
[docker]: https://www.docker.com/
[installer]: ../scripts/install.sh
[readme]: ../README.md#try-in-docker
[testing]: testing.md
