# Getting started

## Look before installing

[Try ds in Docker][try] applies a layer inside a throwaway container and
opens a shell in it. Nothing is written to your home, so it answers "what does
this feel like" without a decision.

## Install

Follow [Install on a machine][install-main] for macOS, Ubuntu, Debian, Alpine,
Fedora, or CentOS Stream. `sh ds-install.sh --no-apply` prepares sources and
runtimes, then previews `core`. Without that flag it applies the layer. The
installer clones `main` outside a checkout and needs no published release.

## Apply core safely

`ds status` and `ds apply` use the selected layer union, initially `core`.
Choose an explicit layer to inspect or apply another preset:

```sh
./ds status core
./ds apply core --dry-run
```

State has three useful summaries:

- `complete`: every component and managed file is present;
- `incomplete`: one or more entries are missing or unavailable;
- `conflict`: a managed target exists with different ownership or content.

Apply refuses conflicts:

```sh
./ds apply core
```

If a conflict should be preserved and replaced, use `--force`:

```sh
./ds apply core --force --dry-run
./ds apply core --force
```

Each conflicting target is backed up to `<target>.ds-adopted` before it is
replaced. `--force` never follows a linked Zsh rc into another repository.

## Use the remote layer

`remote` is an extended local preset. It includes every `core` component
and adds the tools listed under [Layers][layers]. SSH delivery uses
`ds push HOST LAYER`:

```sh
./ds apply remote --dry-run
./ds apply remote
./ds status remote --verbose
```

On macOS, Docker must already be available through Docker Desktop, OrbStack, or
another compatible engine. On Linux, apply reuses a ready engine or selects the
rootless path when the required user-namespace and systemd capabilities exist.

Skip Docker only on a deliberately restricted host:

```sh
./ds apply remote --skip docker
```

The layer remains incomplete until Docker is ready.

## Recovery

```sh
./ds remove core
```

Removal deletes only exact links and marker blocks owned by `ds`. It restores
available `.ds-adopted` backups when the original target is absent. Installed
system packages, mise tools, and versioned snapshots are additive and remain on
disk.

`--force` refuses to overwrite an existing `.ds-adopted` backup.

[install-main]: ../README.md#install-on-a-machine
[layers]: ../README.md#layers
[try]: try.md
