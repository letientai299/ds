package ds

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/letientai299/ds/internal/assets"
)

func sourceFixture(t *testing.T, root string, repos map[assets.Repo]RepoSource) *fixture {
	t.Helper()
	f := newFixture(t)
	f.env.Source = assets.Checkout{Root: root}
	f.env.Repos = repos
	f.env.Environ = f.env.Environ.with("PATH", "/usr/bin:/bin:/opt/homebrew/bin",
		"GIT_CONFIG_GLOBAL", "/dev/null", "GIT_AUTHOR_NAME", "t", "GIT_AUTHOR_EMAIL", "t@example.invalid",
		"GIT_COMMITTER_NAME", "t", "GIT_COMMITTER_EMAIL", "t@example.invalid")
	return f
}

func TestSyncSources(t *testing.T) {
	t.Parallel()
	for _, name := range []string{"behind", "diverged", "ahead", "conflict", "dirty", "detached", "no upstream", "push rejected", "feature branch", "existing operation", "dry run"} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			dir := t.TempDir()
			rootOrigin, root := cloneWithUpstream(t, dir, "ds")
			origin, nvim := cloneWithUpstream(t, dir, "nvim.conf")
			kittyOrigin, kitty := cloneWithUpstream(t, dir, "kitty.conf")
			for _, remote := range []string{rootOrigin, kittyOrigin} {
				writeFile(t, filepath.Join(remote, "f"), "remote\n")
				git(t, remote, "commit", "-qam", "remote")
			}
			writeFile(t, filepath.Join(kitty, "f"), "discard\n")
			writeFile(t, filepath.Join(kitty, "untracked"), "discard\n")
			if name != "ahead" {
				writeFile(t, filepath.Join(origin, "f"), "remote\n")
				git(t, origin, "commit", "-qam", "remote")
			}
			warning := ""
			switch name {
			case "diverged", "ahead", "feature branch", "push rejected":
				if name == "feature branch" {
					git(t, nvim, "checkout", "-qb", "topic")
				}
				writeFile(t, filepath.Join(nvim, "local"), "local\n")
				git(t, nvim, "add", "local")
				git(t, nvim, "commit", "-qm", "local")
				if name == "push rejected" {
					writeExec(t, filepath.Join(origin, ".git", "hooks", "pre-receive"), "#!/bin/sh\nexit 1\n")
					warning = "push failed"
				}
			case "conflict":
				writeFile(t, filepath.Join(nvim, "f"), "conflict\n")
				git(t, nvim, "commit", "-qam", "conflict")
				warning = "rebase aborted"
			case "dirty":
				writeFile(t, filepath.Join(nvim, "local"), "dirty\n")
			case "detached":
				git(t, nvim, "checkout", "-q", "--detach")
				warning = "detached HEAD"
			case "no upstream":
				git(t, nvim, "branch", "--unset-upstream")
			case "existing operation":
				mustMkdir(t, filepath.Join(nvim, ".git", "sequencer"))
				warning = "git operation in progress"
			}
			before := git(t, nvim, "rev-parse", "HEAD")
			remoteBefore := git(t, origin, "rev-parse", "HEAD")
			f := sourceFixture(t, root, map[assets.Repo]RepoSource{
				assets.Nvim: {Dir: nvim}, assets.Kitty: {Dir: kitty, Managed: true},
				assets.Tmux: {Dir: filepath.Join(dir, "absent")},
			})
			dryRun := name == "dry run"
			if err := f.env.SyncSources(context.Background(), dryRun); err != nil {
				t.Fatal(err)
			}
			if warning != "" {
				if !strings.Contains(f.err.String(), "warning:") || !strings.Contains(f.err.String(), warning) {
					t.Fatal(f.err.String())
				}
				if git(t, nvim, "rev-parse", "HEAD") != before {
					t.Fatal("failed sync changed HEAD")
				}
				if git(t, origin, "rev-parse", "HEAD") != remoteBefore {
					t.Fatal("failed sync pushed")
				}
			} else if strings.Contains(f.err.String(), "warning:") {
				t.Fatal(f.err.String())
			}
			if dryRun {
				if git(t, root, "rev-parse", "HEAD") == git(t, rootOrigin, "rev-parse", "HEAD") ||
					git(t, nvim, "rev-parse", "HEAD") != before || git(t, origin, "rev-parse", "HEAD") != remoteBefore ||
					readFile(t, filepath.Join(kitty, "f")) != "discard\n" {
					t.Fatal("dry run mutated repositories")
				}
				return
			}
			if git(t, root, "rev-parse", "HEAD") != git(t, rootOrigin, "rev-parse", "HEAD") {
				t.Fatal("other repository did not sync")
			}
			if readFile(t, filepath.Join(kitty, "f")) != "remote\n" || exists(filepath.Join(kitty, "untracked")) {
				t.Fatal("managed reset failed")
			}
			if name == "conflict" {
				if exists(filepath.Join(nvim, ".git", "rebase-merge")) || git(t, nvim, "status", "--porcelain") != "" {
					t.Fatal("rebase was not aborted")
				}
			}
			if warning == "" {
				branch := "main"
				if name == "feature branch" {
					branch = "topic"
				}
				if git(t, nvim, "rev-parse", "HEAD") != git(t, origin, "rev-parse", branch) {
					t.Fatal("local commits were not pushed")
				}
				if name == "diverged" || name == "feature branch" {
					if git(t, nvim, "rev-parse", "HEAD^") != remoteBefore || readFile(t, filepath.Join(nvim, "local")) != "local\n" {
						t.Fatal("local commit was not rebased")
					}
				}
				if name == "feature branch" && git(t, origin, "rev-parse", "main") != remoteBefore {
					t.Fatal("push changed origin/main")
				}
			}
		})
	}
}

type fetchBarrier struct {
	Runner
	started chan string
	release <-chan struct{}
}

func (r fetchBarrier) Run(ctx context.Context, c Cmd) error {
	if len(c.Args) > 3 && c.Args[0] == "git" && c.Args[3] == "fetch" {
		r.started <- c.Args[2]
		select {
		case <-r.release:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	return r.Runner.Run(ctx, c)
}

func TestSyncSourcesConcurrent(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	_, root := cloneWithUpstream(t, dir, "ds")
	_, nvim := cloneWithUpstream(t, dir, "nvim.conf")
	alias := filepath.Join(dir, "alias")
	if err := os.Symlink(nvim, alias); err != nil {
		t.Fatal(err)
	}
	f := sourceFixture(t, root, map[assets.Repo]RepoSource{assets.Nvim: {Dir: nvim}, assets.Tmux: {Dir: alias}})
	release := make(chan struct{})
	started := make(chan string, 4)
	f.env.Runner = fetchBarrier{Runner: f.env.Runner, started: started, release: release}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- f.env.SyncSources(ctx, false) }()
	seen := map[string]bool{}
	for range 2 {
		select {
		case repo := <-started:
			seen[repo] = true
		case <-ctx.Done():
			close(release)
			<-done
			t.Fatal("fetches did not overlap")
		}
	}
	close(release)
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if len(seen) != 2 || len(started) != 0 {
		t.Fatal("repositories were not deduplicated")
	}
	if strings.Contains(f.err.String(), "warning:") {
		t.Fatal(f.err.String())
	}
}

func TestSyncSourcesCanceled(t *testing.T) {
	t.Parallel()
	_, root := cloneWithUpstream(t, t.TempDir(), "ds")
	f := sourceFixture(t, root, nil)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := f.env.SyncSources(ctx, false); !errors.Is(err, context.Canceled) {
		t.Fatalf("error = %v", err)
	}
}

func TestSyncDirtySource(t *testing.T) {
	t.Parallel()
	for _, name := range []string{"success", "rebase conflict", "unstash conflict", "untracked conflict", "push failure", "push failure tracked only", "fetch failure", "stash failure", "stash lookup", "stash inspect failure", "deleted addition", "empty index", "empty worktree", "canceled", "dry run"} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			dir := t.TempDir()
			origin, repo := cloneWithUpstream(t, dir, "ds")
			for _, path := range []string{"tracked", "removed", "staged-delete"} {
				writeFile(t, filepath.Join(origin, path), "original\n")
			}
			git(t, origin, "add", ".")
			git(t, origin, "commit", "-qm", "files")
			git(t, repo, "pull", "-q", "--ff-only")
			writeFile(t, filepath.Join(repo, "older"), "older stash\n")
			git(t, repo, "stash", "push", "-u", "-m", "older")
			if name == "rebase conflict" {
				writeFile(t, filepath.Join(repo, "f"), "local commit\n")
				git(t, repo, "commit", "-qam", "local")
			}
			if strings.HasPrefix(name, "push failure") {
				writeFile(t, filepath.Join(repo, "local-commit"), "committed\n")
				git(t, repo, "add", "local-commit")
				git(t, repo, "commit", "-qm", "local")
			}
			writeFile(t, filepath.Join(repo, "tracked"), "staged\n")
			git(t, repo, "add", "tracked")
			writeFile(t, filepath.Join(repo, "tracked"), "unstaged\n")
			if err := os.Remove(filepath.Join(repo, "removed")); err != nil {
				t.Fatal(err)
			}
			git(t, repo, "rm", "-q", "staged-delete")
			writeFile(t, filepath.Join(repo, "staged-add"), "added\n")
			git(t, repo, "add", "staged-add")
			if name != "push failure tracked only" {
				writeFile(t, filepath.Join(repo, "new", "untracked"), "untracked\n")
			}
			if name == "deleted addition" {
				if err := os.Remove(filepath.Join(repo, "staged-add")); err != nil {
					t.Fatal(err)
				}
			}
			if name == "empty index" {
				git(t, repo, "rm", "-rf", "--", ".")
			}
			if name == "empty worktree" {
				for path := range strings.SplitSeq(git(t, repo, "ls-files"), "\n") {
					if err := os.Remove(filepath.Join(repo, path)); err != nil && !os.IsNotExist(err) {
						t.Fatal(err)
					}
				}
			}
			writeFile(t, filepath.Join(origin, "f"), "remote\n")
			if name == "unstash conflict" {
				writeFile(t, filepath.Join(origin, "tracked"), "remote conflict\n")
			}
			if name == "untracked conflict" {
				writeFile(t, filepath.Join(origin, "new", "untracked"), "remote file\n")
				git(t, origin, "add", "new")
			}
			git(t, origin, "commit", "-qam", "remote")
			if strings.HasPrefix(name, "push failure") {
				writeExec(t, filepath.Join(origin, ".git", "hooks", "pre-receive"), "#!/bin/sh\nexit 1\n")
			}
			if name == "fetch failure" {
				git(t, repo, "remote", "set-url", "origin", filepath.Join(dir, "absent"))
			}
			head := git(t, repo, "rev-parse", "HEAD")
			remote := git(t, origin, "rev-parse", "HEAD")
			before := sourceState(t, repo)
			f := sourceFixture(t, repo, nil)
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			if name == "stash failure" {
				f.env.Runner = stashFailure{Runner: f.env.Runner}
			}
			if name == "canceled" {
				f.env.Runner = stashFailure{Runner: f.env.Runner, cancel: cancel}
			}
			if strings.HasPrefix(name, "stash lookup") || name == "stash inspect failure" {
				f.env.Runner = stashLookupFailure{Runner: f.env.Runner, before: name == "stash inspect failure"}
			}
			err := f.env.SyncSources(ctx, name == "dry run")
			if name == "canceled" && !errors.Is(err, context.Canceled) {
				t.Fatalf("error = %v", err)
			} else if name != "canceled" && err != nil {
				t.Fatal(err)
			}
			failed := name != "success" && name != "dry run" && name != "stash lookup" && name != "deleted addition"
			if strings.Contains(f.err.String(), "warning:") != failed || strings.Contains(f.err.String(), "rollback failed") {
				t.Fatal(f.err.String())
			}
			after := sourceState(t, repo)
			for i := range before {
				if before[i] != after[i] {
					t.Fatalf("state %d changed:\nbefore %s\nafter %s\n%s", i, before[i], after[i], f.err.String())
				}
			}
			if name != "push failure tracked only" && readFile(t, filepath.Join(repo, "new", "untracked")) != "untracked\n" {
				t.Fatal("untracked file changed")
			}
			if failed || name == "dry run" {
				if git(t, repo, "rev-parse", "HEAD") != head {
					t.Fatal("original HEAD was not restored")
				}
			} else if git(t, repo, "rev-parse", "HEAD") != remote {
				t.Fatal("dirty checkout did not sync")
			}
			if git(t, origin, "rev-parse", "HEAD") != remote {
				t.Fatal("failed sync changed remote")
			}
		})
	}
}

type stashFailure struct {
	Runner
	cancel context.CancelFunc
}

func (r stashFailure) Run(ctx context.Context, c Cmd) error {
	if len(c.Args) > 4 && c.Args[3] == "stash" && c.Args[4] == "push" {
		if err := r.Runner.Run(ctx, c); err != nil {
			return err
		}
		if r.cancel != nil {
			r.cancel()
			return context.Canceled
		}
		return errors.New("stash interrupted after creation")
	}
	return r.Runner.Run(ctx, c)
}

func sourceState(t *testing.T, repo string) [4]string {
	t.Helper()
	return [4]string{git(t, repo, "status", "--porcelain"), git(t, repo, "diff", "--binary"), git(t, repo, "diff", "--cached", "--binary"), git(t, repo, "stash", "list")}
}

type stashLookupFailure struct {
	Runner
	before bool
}

func (r stashLookupFailure) Run(ctx context.Context, c Cmd) error {
	if len(c.Args) > 5 && ((r.before && c.Args[3] == "stash" && c.Args[4] == "list") ||
		(!r.before && c.Args[3] == "rev-parse" && c.Args[5] == "refs/stash")) {
		return errors.New("stash lookup interrupted")
	}
	return r.Runner.Run(ctx, c)
}

type sourceActivity struct {
	Runner
	mu                         sync.Mutex
	active, maximum, completed int
}

func (r *sourceActivity) Run(ctx context.Context, c Cmd) error {
	if len(c.Args) > 3 && c.Args[3] == "symbolic-ref" {
		r.mu.Lock()
		r.active++
		r.maximum = max(r.maximum, r.active)
		r.mu.Unlock()
	}
	err := r.Runner.Run(ctx, c)
	if len(c.Args) > 4 && c.Args[3] == "stash" && c.Args[4] == "drop" {
		r.mu.Lock()
		r.active--
		r.completed++
		r.mu.Unlock()
	}
	return err
}

func TestSyncSourceWorktrees(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	_, repo := cloneWithUpstream(t, dir, "ds")
	worktree := filepath.Join(dir, "worktree")
	git(t, repo, "worktree", "add", "-qb", "topic", worktree)
	for _, path := range []string{repo, worktree} {
		writeFile(t, filepath.Join(path, "dirty"), path)
	}
	f := sourceFixture(t, repo, map[assets.Repo]RepoSource{assets.Nvim: {Dir: worktree}})
	runner := &sourceActivity{Runner: f.env.Runner}
	f.env.Runner = runner
	if err := f.env.SyncSources(context.Background(), false); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(f.err.String(), "warning:") {
		t.Fatal(f.err.String())
	}
	if runner.maximum != 1 || runner.completed != 2 {
		t.Fatalf("overlapping worktrees: %+v", runner)
	}
	for _, path := range []string{repo, worktree} {
		if readFile(t, filepath.Join(path, "dirty")) != path {
			t.Fatal("worktree edits crossed")
		}
	}
	if git(t, repo, "stash", "list") != "" {
		t.Fatal("worktree stash leaked")
	}
}
