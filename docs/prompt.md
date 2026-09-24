# Zsh prompt

The built-in prompt uses Zsh and Git. No prompt plugin is required.
Open a new shell after installing an updated checkout.

The first line shows the directory, `⑂` branch, Git counts, and latest commit
subject. Long lines truncate to fit the terminal. Detached HEAD shows `@` and
an abbreviated commit ID; repositories without commits omit the commit subject.

| Symbol | Count                                      |
| ------ | ------------------------------------------ |
| `↑`    | Commits ahead of the local upstream ref    |
| `↓`    | Commits behind the local upstream ref      |
| `+`    | Staged paths                               |
| `!`    | Unstaged paths, including dirty submodules |
| `?`    | Untracked entries; directories count once  |
| `×`    | Conflicted paths                           |
| `≡`    | Stash entries                              |

Git status refreshes before each prompt without fetching or locking the index.
The commit subject stays cached until HEAD changes. Large repositories and slow
filesystems can increase refresh time because status runs synchronously.

The second line shows `•` for one background or stopped job and `2•` for two.
A pipeline counts as one job. Command duration appears only above ten seconds;
idle time at the prompt is excluded. The clock uses local time. Failed commands
show a red `[exit_code]❯`; successful commands show a green `❯`.

Run `zsh -df tests/prompt.zsh` for disposable Git fixtures and interactive job
checks. Run `mise run bench:prompt` for refresh latency percentiles across small,
large, dirty, and non-repository directories. `DS_BENCH_SAMPLES` sets repetitions.
The benchmark includes the old static prompt as a baseline.

Implementation: [prompt source][source]. Protocols: [Git status][git-status] and
[Zsh prompt expansion][zsh-prompt].

[source]: ../src/dotfiles/prompt.zsh
[git-status]: https://git-scm.com/docs/git-status
[zsh-prompt]: https://zsh.sourceforge.io/Doc/Release/Prompt-Expansion.html
