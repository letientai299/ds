# Testing

## Main gates

```sh
mise run check
mise run e2e:all
mise run verify
```

`check` runs ShellCheck, C syntax checks, TOML formatting, generated-data
validation, Janet compile checks, unit tests, and shell contracts. The contract
covers all four delivery transports end to end: the release installer, the
served-directory pull with both Curl and Wget, the SSH push, and a manual
archive. It also asserts that reinstalling the same release is idempotent and
that a mismatched archive checksum is rejected.

`e2e:all` launches every end-to-end target concurrently with seven mise jobs. It
uses `--continue-on-error`, so one failure does not discard sibling results.

`verify` adds runtime execution and reproducibility to the static and E2E
matrix.

## End-to-end targets

| Task                   | Coverage                                                                           |
| ---------------------- | ---------------------------------------------------------------------------------- |
| `e2e:containers`       | Gitless snapshots on Alpine and Ubuntu, ARM64 and x64, read-only and unprivileged  |
| `e2e:controller`       | Platform probe, content-addressed SSH push, isolated-home preview, and idempotence |
| `e2e:core`             | Two convergent core applies on Alpine and Ubuntu plus optional Starship lifecycle  |
| `e2e:remote`           | Remote tools and dedicated Tmux behavior on Alpine musl and Ubuntu glibc           |
| `e2e:docker-readiness` | Existing engine, Buildx, Compose, pinned pull/run, and tiny image build/run        |
| `e2e:macos`            | No-write isolated-home previews and Homebrew package selection                     |
| `e2e:rocky`            | DNF, CRB/EPEL preparation, tools, and double-apply convergence                     |

## Docker-readiness scope

Run only the live-engine contract with:

```sh
mise run e2e:docker-readiness
```

This target requires a running Docker-compatible engine. It verifies engine
connectivity, Buildx and Compose commands, a pinned `hello-world` pull/run, a
small pinned Alpine build/run, and Compose configuration parsing.

It does not install Docker, grant group membership, or prove that a rootless
user service survives logout.

## Runtime and performance tasks

```sh
mise run runtime:verify
mise run runtime:reproducible
mise run bench
mise run bench:linux
```

Runtime verification checks architecture, linkage, and actual execution.
Reproducibility builds the matrix twice in isolated roots and compares hashes.
Benchmarks record bundle size, startup, cold/no-op layer behavior, received
bytes, cache use, and component disk size without setting release thresholds.

## Manual boundaries

`mise run try` opens a shell in a container with a layer applied, which covers
the look and feel questions a test suite cannot assert. See
[Try ds in Docker](try.md).

Containers cannot prove:

- a rootless user systemd service survives an actual SSH logout and reconnect;
- OSC 52 reaches the intended terminal clipboard;
- the configuration remains comfortable during normal daily use;
- a real-home adoption matches the user's intended backup boundary.

Keep those results separate from automated E2E evidence.
