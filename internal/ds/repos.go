package ds

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/letientai299/ds/internal/assets"
)

// RepoSource locates a configuration repository on the target.
type RepoSource struct {
	Dir string
	URL string
	// Managed clones belong to ds, so upgrades reset them to the remote
	// head. Other directories belong to the user and only fast-forward
	// when clean.
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

// SyncSources brings source repositories to their remote heads. The ds
// checkout and user repositories fast-forward only when clean and
// tracking; managed clones reset to the remote head.
func (e *Env) SyncSources(ctx context.Context, dryRun bool) error {
	var user, managed []string
	if src, ok := e.Source.(assets.Checkout); ok {
		user = append(user, src.Root)
	}
	for _, repo := range assets.ConfigRepos {
		rs := e.Repos[repo]
		switch {
		case !exists(filepath.Join(rs.Dir, ".git")):
		case rs.Managed:
			managed = append(managed, rs.Dir)
		case !slices.Contains(user, rs.Dir):
			user = append(user, rs.Dir)
		}
	}
	git := func(dir string, args ...string) (string, error) {
		return output(ctx, e.Runner, Cmd{Args: append([]string{"git", "-C", dir}, args...), Env: e.gitEnv()})
	}
	var problems []string
	for _, dir := range user {
		if _, err := git(dir, "symbolic-ref", "-q", "HEAD"); err != nil {
			problems = append(problems, dir+": detached HEAD")
			continue
		}
		if status, err := git(dir, "status", "--porcelain", "--untracked-files=normal"); err != nil || status != "" {
			problems = append(problems, dir+": uncommitted changes")
			continue
		}
		if _, err := git(dir, "rev-parse", "--verify", "@{upstream}"); err != nil {
			problems = append(problems, dir+": branch has no upstream")
		}
	}
	if len(problems) > 0 {
		return fmt.Errorf("sources not ready:\n  %s", strings.Join(problems, "\n  "))
	}
	run := func(dir string, args ...string) error {
		c := Cmd{Args: append([]string{"git", "-C", dir}, args...), Env: e.gitEnv(), Stdout: e.Stderr, Stderr: e.Stderr}
		return e.Runner.Run(ctx, c)
	}
	var advanced []string
	sync := func(dir, verb string, steps ...[]string) error {
		if dryRun {
			e.printf("ds: would %s %s\n", verb, dir)
			return nil
		}
		before, _ := git(dir, "rev-parse", "HEAD")
		e.printf("ds: %s %s\n", verb, dir)
		for _, step := range steps {
			if err := run(dir, step...); err != nil {
				msg := fmt.Sprintf("%s %s: %v", verb, dir, err)
				if len(advanced) > 0 {
					msg += "\nalready advanced: " + strings.Join(advanced, ", ")
				}
				return errors.New(msg)
			}
		}
		if after, _ := git(dir, "rev-parse", "HEAD"); after != before {
			advanced = append(advanced, dir)
		}
		return nil
	}
	for _, dir := range user {
		if err := sync(dir, "fast-forward", []string{"-c", "rebase.autostash=false", "pull", "--ff-only", "--no-rebase"}); err != nil {
			return err
		}
	}
	for _, dir := range managed {
		err := sync(dir, "reset",
			[]string{"fetch", "--quiet", "--depth", "1", "origin", "HEAD"},
			[]string{"reset", "--quiet", "--hard", "FETCH_HEAD"},
			[]string{"clean", "--quiet", "-fd"})
		if err != nil {
			return err
		}
	}
	return nil
}
