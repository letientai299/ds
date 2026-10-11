# Testing

```sh
mise run lint
mise run test
mise run test:zsh
mise run dist
```

Go tests use temporary homes, fake `mise`, `nvim`, and `ssh` commands, local Git
repositories, and an in-process download site. They cover selector rules,
additive selection, dependencies, idempotent convergence, previews that write
nothing, conflicts and backups, user mise pins, rc symlinks, explicit-home
isolation, locking, partial failures and retries, trial isolation, snapshot
modes and hidden files, repository placement, clones, and source sync,
main-build staging and activation, checksum and publication races, SSH argument
quoting, and transfer cleanup.

`mise run dist` builds every platform into `dist/`. Serve that directory and set
`DS_DOWNLOAD_URL` to exercise `upgrade` and `deploy` against local builds.

## CI

| Job       | Checks                                                                |
| --------- | --------------------------------------------------------------------- |
| `test`    | Lint, Go tests, and Zsh prompt tests on Ubuntu and macOS              |
| `dist`    | Checkout-mode preview against fetched sources, all builds, linkage    |
| `linux`   | Execution on amd64 and arm64; Ubuntu provisioning on `main`           |
| `macos`   | Both macOS architectures; full provisioning in a temporary home       |
| `publish` | Pages deployment and a bootstrap run against the live site, on `main` |

Online provisioning runs only outside pull requests so tool downloads do not
gate offline behavior checks.
