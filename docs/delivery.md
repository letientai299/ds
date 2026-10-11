# Main builds and delivery

The [CI workflow][ci] builds `darwin/arm64`, `darwin/amd64`, `linux/arm64`, and
`linux/amd64` with `CGO_ENABLED=0`. Successful runs on `main` publish the
binaries through [GitHub Pages deployed by Actions][pages]. There are no tags,
releases, or historical builds; the site holds only the latest build.

## Snapshots

[`ds-build dist`][ds-build] exports the ds `assets/` directory only: tracked and
untracked files that Git does not ignore, with hidden files, executable modes,
and in-repository symlinks, into a deterministic gzip tar. [Go embedding][embed]
compiles the tar and build metadata into the binary. Configuration repositories
are not embedded; hosts clone them on first use, so their changes reach hosts on
the next `ds upgrade` without a ds build.

The build ID combines the ds commit, a digest of every ds source file, and the
exported content. `ds version` prints it with the workflow run and the commit of
each cloned configuration repository.

## Published files

| File                     | Purpose                                           |
| ------------------------ | ------------------------------------------------- |
| `manifest.json`          | Build ID, commits, workflow run, SHA-256 per file |
| `latest.tsv`             | The same platform rows for the shell bootstrap    |
| `bootstrap.sh`           | POSIX installer                                   |
| `ds-<build>-<os>-<arch>` | Platform binaries                                 |

Clients refetch the manifest when a binary is missing or fails its checksum,
because the site can change between requests. Both the Go client and the
bootstrap retry a fixed number of times and never run an unverified binary.

## Publication order

The publish job runs only on `main` after tests, builds, and platform checks
pass, and only that job holds Pages permissions. A `pages` concurrency group
serializes publication. Before deploying, the job compares its run ID with the
published manifest and skips when a newer run already published. After
deploying, it waits for the new manifest and runs the bootstrap against the live
site.

## Setup

1. In repository settings, set Pages to deploy from GitHub Actions.
2. Run the workflow on `main` and confirm the bootstrap step passes.

The site lives under the owner's Pages domain, `https://letientai.io/ds`.

`DS_DOWNLOAD_URL`, or `download_url` in `<config>/ds/config.toml`, points ds at
another site.

## SSH deployment

`ds deploy HOST` probes the platform with `uname`, downloads and verifies the
matching binary on the controller, streams it over OpenSSH into a temporary
directory under the remote cache directory, and runs its `add` with the given
selectors, or `-l core`. Remote commands are single-line `sh -c` calls with
quoted arguments, so homes with spaces and csh login shells work. A shell trap
removes the transferred binary on exit; installed builds stay under the selected
home. OpenSSH aliases, ProxyJump, and agents work unchanged. The target needs no
Go, archive tool, or GitHub token, but it needs HTTPS access to GitHub: ds
installs Git when missing and clones the configuration repositories there.
Checkout and main callers deploy the same latest build.

[ci]: ../.github/workflows/ci.yml
[ds-build]: ../cmd/ds-build/main.go
[embed]: https://pkg.go.dev/embed
[pages]:
  https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages
