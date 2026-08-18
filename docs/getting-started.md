# Getting started

## Requirements

The controller checkout supports macOS and Linux on ARM64 and x64. Building the
complete runtime matrix requires mise, Git, a C toolchain, and Docker. Applying
a delivered snapshot does not require Git, Janet, mise, or a downloader to be
preinstalled on the target.

The checkout expects these configuration sources:

- `../nvim.conf`, or a path supplied through `DF_NVIM_SOURCE`;
- `../tmux.conf`, or a path supplied through `DF_TMUX_SOURCE` for `remote`.

Delivery bundles contain committed Git exports of both sources.

## Prepare the checkout

```sh
mise install
mise run runtime:build
mise run runtime:fetch-mise
mise run check
```

The first command installs development tooling selected by `.miserc.toml`.
Runtime tasks build Janet and fetch mise for macOS and Linux, ARM64 and x64.

## Apply core safely

Always inspect the current state first:

```sh
./ds status core
./ds diff core
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

If a conflict should be preserved and replaced, use adoption:

```sh
./ds adopt core --dry-run
./ds adopt core
```

Each conflicting target moves to `<target>.df-adopted`. Adoption never follows
a linked Zsh rc into another repository.

## Use the remote layer

`remote` includes every `core` component and adds Tmux, Docker readiness,
Zoxide, Bat, and Delta:

```sh
./ds apply remote --dry-run
./ds apply remote
./ds doctor remote
```

On macOS, Docker must already be available through Docker Desktop, OrbStack, or
another compatible engine. On Linux, apply reuses a ready engine or selects the
rootless path when the required user-namespace and systemd capabilities exist.

Skip Docker only on a deliberately restricted host:

```sh
./ds apply remote --skip docker
```

The layer remains incomplete until Docker is ready.

## Optional Starship prompt

```sh
./ds add starship --dry-run
./ds add starship
./ds status starship
```

Remove the selection with:

```sh
./ds unapply starship
```

## Recovery

```sh
./ds unapply core
```

Unapply removes only exact links and marker blocks owned by `df`. It restores
available `.df-adopted` backups when the original target is absent. Installed
system packages, mise tools, and versioned snapshots are additive and remain on
disk.

Avoid `ds force` unless discarding each reported conflict is intentional. It
removes conflicting targets without backups.
