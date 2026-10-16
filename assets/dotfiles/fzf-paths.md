# Fzf helper maintenance

`fzf-files` and `fzf-dirs` share [fzf-paths.zsh][helper] so shell pickers and
Neovim use the same selection rules. The wrappers resolve their real paths,
including installed symlinks, and supply the requested entry type. ds supplies
Zsh, fd, and GNU awk; dependency detection and alternate command names belong
in deployment, not in each search invocation.

## Preserve selection behavior

The result is the union of normally visible paths and explicitly included
ignored paths. Hidden entries remain eligible. `.git` stays excluded.

A normal fd walk preserves ignore-file behavior. A second, unignored walk
finds configured names beneath ignored parents. Removing that second walk
loses entries such as `nested/local/config.lua` or an ignored directory's
`.env`. Replacing both walks with unrestricted traversal exposes unrelated
ignored files. Any replacement must preserve this union.

Extend [fzf-includes.zsh][includes] rather than adding branches to the helper.
Directory entries are literal names at any depth and include descendants.
Filename patterns match basenames, support `*` and `?`, and apply only to file
selection. Other regex metacharacters remain literal. Wildcards cannot cross
`/`. Match case explicitly: fd's default smart-case behavior would otherwise
change when an uppercase letter appears in the checkout's absolute path.

The skip list prunes only the additional unignored walk. Applying it to the
normal walk would hide normally visible files in directories such as `build`.
It also prevents a requested name inside an ignored dependency tree from
forcing that tree into the additional results.

fd's full-path regex sees the physical cwd. Resolve symlinked cwd paths before
constructing the regex, and escape the root as literal text. Anchor matching
after that root: a checkout beneath an ancestor named `local` must not include
every ignored file merely because the ancestor matches an include name.

Output contains unique, newline-delimited paths relative to the cwd. Spaces
and Unicode remain part of a path; embedded newlines cannot be represented by
this protocol. Supporting those requires coordinating NUL-delimited output
with every shell and Neovim consumer.

## Preserve streaming and failure behavior

File walks overlap to reduce total latency. Their output streams stay
separate: concurrent writers can interleave chunks of long path lines in a
shared pipe. Drain normal results first, then the coprocess pipe, and retain
its PID. Explicitly waiting for that PID propagates a failed unignored scan;
reading its output alone does not report its exit status.

Directory walks remain sequential. Parallel walks improved some completion
times but delayed the first directory result in larger checkouts. Interactive
pickers need both low first-result latency and low total latency.

The final awk filter removes overlaps while preserving arrival order. Flush
the first emitted result so buffering cannot hold the picker's initial result.
Flushing every record increased write traffic without a consistent latency
benefit. Sorting would delay streaming and add work solely to remove duplicates.

## Optimization lessons

Native Zsh substitutions escape regex text without launching a process for
every include entry. Adding sd to core does not make those process launches
free; retain native escaping unless whole-helper measurements justify changing
it. Do not infer helper speed from an isolated text-filter microbenchmark.
Faster standalone deduplication filters did not consistently improve complete
helper latency. Any replacement must compare actual path strings; storing only
hash fingerprints can discard distinct paths after a collision.

The shared fd thread limit bounds CPU use, particularly on many-core Linux
hosts. Unrestricted thread counts spent extra work starting and coordinating
workers. Lower limits slowed larger Mac walks; higher limits did not improve
consistently. Treat the current limit as a measured compromise, not a universal
filesystem optimum. Startup-file suppression also showed no consistent gain.

These choices were tested against real source trees on macOS and Ubuntu,
using both full working trees and smaller tracked-source snapshots. Snapshots
do not represent the ignored-file volume of full working trees.
Absolute timings depend on checkout contents, filesystem caches, and host load.

## Validate future changes

Run `mise run test:zsh`; [the fzf regression tests][tests] cover nested ignored
entries, skip rules, metacharacters, wildcard boundaries, symlinked cwd and
executables, duplicate removal, empty include lists, and fd failures.

For performance changes, compare the committed helper with the candidate on
real checkouts of different sizes. Use the same ds-managed tools, warm both
variants, alternate execution order, and collect repeated samples. Check exact
path-set equality and duplicate absence on every run; fixture correctness and
benchmark equivalence answer different questions.

Measure time to first output, total completion time, and summed child CPU time
separately. More parallelism can lower wall time while increasing CPU use.
Record source hashes, tool versions, corpus provenance, and output hashes.
Set each subprocess cwd explicitly: `mise -C / exec` changes cwd and can turn a
checkout benchmark into an unintended filesystem-wide search.

Collect profiles separately from timings. Linux syscall summaries expose
thread creation and traversal work; Mac sampling exposes worker stacks.
Tracing and attaching change scheduling, so profiled runtimes do not establish
speedups. Short samples of stripped binaries support only limited attribution.

[helper]: ./fzf-paths.zsh
[includes]: ./fzf-includes.zsh
[tests]: ../../tests/fzf-paths.zsh
