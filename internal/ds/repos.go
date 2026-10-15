package ds

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/letientai299/ds/internal/assets"
)

// RepoSource locates a configuration repository on the target.
type RepoSource struct {
	Dir string
	URL string
	// User checkouts rebase; managed clones reset.
	Managed bool
}

// ResolveRepos places configuration repositories: configured paths first,
// then siblings of a checkout, then ds-managed clones under the data
// directory.
func (c UserConfig) ResolveRepos(cat *Catalog, src assets.Source, p Paths) (map[assets.Repo]RepoSource, error) {
	repos := map[assets.Repo]RepoSource{}
	for _, repo := range assets.ConfigRepos {
		rs := RepoSource{URL: cat.RepoURL(repo)}
		switch checkout, ok := src.(assets.Checkout); {
		case c.Sources[string(repo)] != "":
			abs, err := absHome(c.Sources[string(repo)], p.Home)
			if err != nil {
				return nil, err
			}
			rs.Dir = abs
		case ok:
			rs.Dir = filepath.Join(filepath.Dir(checkout.Root), repo.CheckoutName())
		default:
			rs.Dir, rs.Managed = filepath.Join(p.DSData(), "sources", repo.CheckoutName()), true
		}
		repos[repo] = rs
	}
	return repos, nil
}

func (e *Env) gitEnv() envList { return e.Environ.with("GIT_TERMINAL_PROMPT", "0") }

func (e *Env) cloneRepo(ctx context.Context, a CloneRepo) error {
	if err := os.MkdirAll(filepath.Dir(a.Dir), 0o755); err != nil {
		return err
	}
	args := []string{"git", "clone", "--quiet"}
	if a.Shallow {
		args = append(args, "--depth", "1")
	}
	return e.Runner.Run(ctx, Cmd{Args: append(args, "--", a.URL, a.Dir), Env: e.gitEnv(), Stdout: e.Stderr, Stderr: e.Stderr})
}

// SyncSources synchronizes repositories concurrently before handoff.
func (e *Env) SyncSources(ctx context.Context, dryRun bool) error {
	var sources []RepoSource
	if src, ok := e.Source.(assets.Checkout); ok {
		sources = append(sources, RepoSource{Dir: src.Root})
	}
	for _, repo := range assets.ConfigRepos {
		if rs := e.Repos[repo]; exists(filepath.Join(rs.Dir, ".git")) {
			sources = append(sources, rs)
		}
	}
	var workers sync.WaitGroup
	var report sync.Mutex
	var repositories sync.Map
	seen := map[string]bool{}
	for _, rs := range sources {
		dir, err := filepath.EvalSymlinks(rs.Dir)
		if err != nil {
			dir = rs.Dir
		}
		if seen[dir] {
			continue
		}
		seen[dir] = true
		rs.Dir = dir
		workers.Go(func() {
			var log bytes.Buffer
			worker := *e
			worker.Stderr = &log
			common, err := worker.sourceGit(ctx, rs.Dir, "rev-parse", "--path-format=absolute", "--git-common-dir")
			if err == nil {
				lock, _ := repositories.LoadOrStore(common, new(sync.Mutex))
				mutex := lock.(*sync.Mutex)
				mutex.Lock()
				if rs.Managed {
					err = worker.resetSource(ctx, rs.Dir, dryRun)
				} else {
					err = worker.syncSource(ctx, rs.Dir, dryRun)
				}
				mutex.Unlock()
			}
			if err != nil {
				worker.printf("warning: %s: %v; fix manually\n", rs.Dir, err)
			}
			report.Lock()
			e.printf("%s", log.String())
			report.Unlock()
		})
	}
	workers.Wait()
	return ctx.Err()
}

func (e *Env) sourceGit(ctx context.Context, dir string, args ...string) (string, error) {
	return output(ctx, e.Runner, Cmd{
		Args:    append([]string{"git", "-C", dir}, args...),
		Env:     e.gitEnv().with("GIT_EDITOR", "true", "GIT_SEQUENCE_EDITOR", "true"),
		Timeout: 2 * time.Minute,
	})
}

func (e *Env) resetSource(ctx context.Context, dir string, dryRun bool) error {
	if dryRun {
		e.printf("ds: would reset %s\n", dir)
		return nil
	}
	for _, args := range [][]string{
		{"fetch", "--quiet", "--depth", "1", "origin", "HEAD"},
		{"reset", "--quiet", "--hard", "FETCH_HEAD"},
		{"clean", "--quiet", "-fd"},
	} {
		if _, err := e.sourceGit(ctx, dir, args...); err != nil {
			return err
		}
	}
	e.printf("ds: reset %s\n", dir)
	return nil
}

func (e *Env) syncSource(ctx context.Context, dir string, dryRun bool) (result error) {
	git := func(ctx context.Context, args ...string) (string, error) {
		return e.sourceGit(ctx, dir, args...)
	}
	branch, err := git(ctx, "symbolic-ref", "-q", "HEAD")
	if err != nil {
		return errors.New("detached HEAD")
	}
	gitDir, err := git(ctx, "rev-parse", "--absolute-git-dir")
	if err != nil {
		return err
	}
	for _, state := range []string{"rebase-merge", "rebase-apply", "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "sequencer"} {
		if exists(filepath.Join(gitDir, state)) {
			return errors.New("git operation in progress")
		}
	}
	status, err := git(ctx, "status", "--porcelain", "--untracked-files=normal")
	if err != nil {
		return err
	}
	if dryRun {
		if status != "" {
			e.printf("ds: would stash and restore changes in %s\n", dir)
		}
		e.printf("ds: would fetch, rebase origin/main, push %s\n", dir)
		return nil
	}
	if _, err := git(ctx, "fetch", "--quiet", "--no-tags", "origin", "refs/heads/main:refs/remotes/origin/main"); err != nil {
		return err
	}
	head, err := git(ctx, "rev-parse", "HEAD")
	if err != nil {
		return err
	}
	deleted, err := git(ctx, "diff", "--raw", "-z", "--no-renames", "--diff-filter=D")
	if err != nil {
		return err
	}
	stash := ""
	rollback := false
	defer func() {
		if result == nil || !rollback {
			return
		}
		cleanup, cancel := context.WithTimeout(context.WithoutCancel(ctx), 30*time.Second)
		defer cancel()
		if err := e.restoreSource(cleanup, dir, gitDir, head, stash, deleted); err != nil {
			result = fmt.Errorf("%w; rollback failed: %v; stash %s retained", result, err, stash)
		}
	}()
	if status != "" {
		stash, result = e.stashSource(ctx, dir)
		rollback = stash != ""
		if result != nil {
			return result
		}
	}
	rollback = true
	if _, err := git(ctx, "-c", "rebase.updateRefs=false", "rebase", "--no-autostash", "--no-fork-point", "origin/main"); err != nil {
		return fmt.Errorf("rebase aborted: %w", err)
	}
	if stash != "" {
		if _, err := git(ctx, "stash", "apply", "--index", stash); err != nil {
			return fmt.Errorf("unstash failed: %w", err)
		}
	}
	if err := restoreDeleted(dir, deleted); err != nil {
		return err
	}
	if _, err := git(ctx, "push", "--quiet", "origin", "HEAD:"+branch); err != nil {
		return fmt.Errorf("push failed: %w", err)
	}
	if stash != "" {
		if err := e.dropSourceStash(ctx, dir, stash); err != nil {
			e.printf("warning: %s: stash %s retained: %v\n", dir, stash, err)
		}
	}
	e.printf("ds: synced %s\n", dir)
	return nil
}

func (e *Env) stashSource(ctx context.Context, dir string) (string, error) {
	previous, err := e.sourceGit(ctx, dir, "stash", "list", "-1", "--format=%H")
	if err != nil {
		return "", err
	}
	_, pushErr := e.sourceGit(ctx, dir, "stash", "push", "--include-untracked", "--message", "ds upgrade")
	inspect, cancel := context.WithTimeout(context.WithoutCancel(ctx), inspectTimeout)
	defer cancel()
	current, err := e.sourceGit(inspect, dir, "rev-parse", "--verify", "refs/stash")
	if err != nil {
		current, err = e.sourceGit(inspect, dir, "stash", "list", "-1", "--format=%H")
	}
	if err != nil {
		return "", fmt.Errorf("stash lookup failed; recover refs/stash: %w", errors.Join(pushErr, err))
	}
	if current == "" || current == previous {
		return "", errors.Join(pushErr, errors.New("stash was not created"))
	}
	return current, pushErr
}

func (e *Env) restoreSource(ctx context.Context, dir, gitDir, head, stash, deleted string) error {
	if exists(filepath.Join(gitDir, "rebase-merge")) || exists(filepath.Join(gitDir, "rebase-apply")) {
		if _, err := e.sourceGit(ctx, dir, "rebase", "--abort"); err != nil {
			return err
		}
	}
	steps := [][]string{{"reset", "--quiet", "--hard", head}}
	if stash != "" {
		// Restore snapshots despite partially applied untracked files.
		steps = append(steps,
			[]string{"read-tree", "--reset", "-u", stash},
			[]string{"read-tree", stash + "^2"})
		untracked, err := e.sourceGit(ctx, dir, "ls-tree", stash+"^3")
		if err != nil {
			return err
		}
		if untracked != "" {
			steps = append(steps, []string{"restore", "--source=" + stash + "^3", "--worktree", "--overlay", "--", "."})
		}
	}
	for _, args := range steps {
		if _, err := e.sourceGit(ctx, dir, args...); err != nil {
			return err
		}
	}
	if err := restoreDeleted(dir, deleted); err != nil {
		return err
	}
	if stash != "" {
		return e.dropSourceStash(ctx, dir, stash)
	}
	return nil
}

func (e *Env) dropSourceStash(ctx context.Context, dir, stash string) error {
	entries, err := e.sourceGit(ctx, dir, "stash", "list", "--format=%H %gd")
	if err != nil {
		return err
	}
	for entry := range strings.SplitSeq(entries, "\n") {
		if hash, ref, ok := strings.Cut(entry, " "); ok && hash == stash {
			_, err := e.sourceGit(ctx, dir, "stash", "drop", "--quiet", ref)
			return err
		}
	}
	return errors.New("upgrade stash is missing")
}

func restoreDeleted(dir, deleted string) error {
	// Stash recreates staged additions deleted before stashing.
	fields := strings.Split(deleted, "\x00")
	for i := 1; i < len(fields); i += 2 {
		if err := os.Remove(filepath.Join(dir, fields[i])); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	return nil
}
