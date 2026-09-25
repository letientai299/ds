# Testing

## Main gates

```sh
mise run check
mise run e2e:all
mise run verify
```

`check` chains three narrower tasks, so the first failure stops the run:
`check:static` (ShellCheck, `shfmt -d`, C syntax and format checks, TOML
formatting, generated-data validation), `check:unit` (Janet compile checks and
unit tests), and `check:contract` (the delivery contract). The first two
together take a few seconds and are the inner loop; run them directly while
iterating. The contract
covers all four delivery transports end to end: the release installer, the
served-directory pull with both Curl and Wget, the SSH push, and a manual
archive. It also asserts that reinstalling the same release is idempotent and
that a mismatched archive checksum is rejected.

The unit gate also exercises CLI argument rejection, removal previews, shell
upgrades, demo cleanup, and both SSH transports using isolated homes and fake
external commands. The approved UX checks also cover version inventory,
JSON/exit contracts, completion, failed activation, rollback, lock contention,
backup preflight, Docker deadlines, and batched checksum fallbacks. These checks
do not provision a real Docker daemon.

`e2e:all` launches every end-to-end target concurrently with seven mise jobs. It
uses `--continue-on-error`, so one failure does not discard sibling results.

`verify` adds runtime execution and reproducibility to the static and E2E
matrix.

## End-to-end targets

| Task                   | Coverage                                                                           |
| ---------------------- | ---------------------------------------------------------------------------------- |
| `e2e:containers`       | Gitless snapshots on Alpine and Ubuntu, ARM64 and x64, read-only and unprivileged  |
| `e2e:controller`       | Platform probe, content-addressed SSH push, isolated-home preview, and idempotence |
| `e2e:core`             | Two convergent core applies on Alpine and Ubuntu                                   |
| `e2e:remote`           | Remote tools, Yazi, and Tmux on Alpine musl and Ubuntu glibc                       |
| `e2e:docker-readiness` | Existing engine, Buildx, Compose, pinned pull/run, and tiny image build/run        |
| `e2e:macos`            | No-write isolated-home previews and Homebrew package selection                     |
| `e2e:rocky`            | DNF, CRB/EPEL preparation, tools, and double-apply convergence                     |

## Target preflight

`mise run preflight` reports whether a machine can receive a push: the delivery
utilities, the Docker prerequisites, and the rootless subordinate-ID ranges.
With no argument it inspects the local machine; pass an SSH host to inspect that
host instead, which needs nothing installed there beforehand.

```sh
mise run preflight
mise run preflight my-host
```

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
[Try ds in Docker][try].

Containers cannot prove:

- a rootless user systemd service survives an actual SSH logout and reconnect;
- OSC 52 reaches the intended terminal clipboard;
- the configuration remains comfortable during normal daily use;
- a real-home adoption matches the user's intended backup boundary.

Keep those results separate from automated E2E evidence.

[try]: try.md
