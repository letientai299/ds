# Testing

## Main gates

```sh
mise run check
mise run e2e:all
mise run verify
```

`check` runs three groups: `check:static` (ShellCheck, `shfmt -d`, TOML
formatting, generated-data validation), `check:unit` (Janet compile checks and
unit tests), and `check:contract` (the delivery contract). Each task runs its
steps concurrently through [`tests/check.sh`][check-sh], which prints failed
step logs at the end. `DS_CHECK_JOBS` caps the concurrency; it defaults to the
CPU count. The contract is the longest step and bounds the run. The script also
takes single step names, such as `tests/check.sh core`.

The contract
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

`e2e:all` runs `e2e:macos` on the host next to `e2e:linux`, which runs every
Linux end-to-end target concurrently in one sandbox. Before the targets start, the sandbox fetches the Janet source and mise, and
builds both Linux runtimes; the host BuildKit cache makes rebuilds fast. One
failure does not discard sibling results.

`verify` runs the check and E2E groups in one sandbox, and adds runtime
execution and reproducibility on the host.

## Test sandbox

Every check, E2E, and `bench:linux` run happens inside one throwaway container
built by [`tests/sandbox.sh`][sandbox-sh] from [`tests/Dockerfile`][dockerfile].
The container gets a read-only mount of the checkout and of the sibling
`nvim.conf`, `tmux.conf`, and `kitty.conf` repositories, and it tests a copy of
the checkout. Its home, mise directories, and temporary files live in a tmpfs
that is gone when the container exits. It runs as your uid with all
capabilities dropped. It keeps network access because the snapshot build
downloads Kitty's Go modules. Export `GITHUB_TOKEN` before E2E runs; the sandbox and the nested
containers forward it by name so mise avoids the unauthenticated GitHub API
rate limit. Only the `ds-test:local` image and its build cache
remain on the host.

`tests/sandbox.sh --docker` also mounts the host Docker socket for the tests
that start their own containers. The engine resolves bind-mount sources on the
host, so in this mode the checkout copy and `TMPDIR` live in a host temporary
directory mounted at the same absolute path. A root container removes that
directory afterwards, because nested root containers leave root-owned files.
Socket access controls the whole engine, and pulled images and the runtime
BuildKit cache stay on the host.

Each test script also calls `isolate_home` from [`tests/isolate.sh`][isolate]
so that running it directly on the host keeps the real home, XDG and mise
directories, and global Git configuration out of reach. `DOCKER_CONFIG` keeps
pointing at the real `~/.docker` so E2E tests reach the engine.

`check:c` compiles and format-checks the Mach-O normalizer against the macOS
SDK, and `e2e:macos` previews macOS applies, so both run on the host and only
on Darwin. `check` depends on `check:c`.

CI runners are already disposable, so CI runs `tests/check.sh` directly without
the container.

## End-to-end targets

| Task                   | Coverage                                                                           |
| ---------------------- | ---------------------------------------------------------------------------------- |
| `e2e:containers`       | Gitless snapshots on Alpine and Ubuntu, ARM64 and x64, read-only and unprivileged  |
| `e2e:controller`       | Platform probe, content-addressed SSH push, isolated-home preview, and idempotence |
| `e2e:core`             | Two convergent core applies on Alpine and Ubuntu                                   |
| `e2e:remote`           | Remote tools, Yazi, and Tmux on Alpine musl and Ubuntu glibc                       |
| `e2e:docker-readiness` | Existing engine, Buildx, Compose, pinned pull/run, and tiny image build/run        |
| `e2e:macos`            | No-write isolated-home previews and Linux package skipping                         |
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
[check-sh]: ../tests/check.sh
[sandbox-sh]: ../tests/sandbox.sh
[dockerfile]: ../tests/Dockerfile
[isolate]: ../tests/isolate.sh
