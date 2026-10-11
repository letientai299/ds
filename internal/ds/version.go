package ds

import (
	"context"
	"fmt"
	"io"
	"maps"
	"slices"

	"github.com/letientai299/ds/internal/assets"
)

// VersionReport identifies the running ds and its assets.
type VersionReport struct {
	Mode       string            `json:"mode"`
	Executable string            `json:"executable"`
	Build      *assets.BuildInfo           `json:"build,omitempty"`
	Checkout   *CheckoutVersion            `json:"checkout,omitempty"`
	Sources    map[assets.Repo]RepoVersion `json:"sources"`
}

// CheckoutVersion describes the live ds checkout.
type CheckoutVersion struct {
	Root   string `json:"root"`
	Commit string `json:"commit"`
	Dirty  bool   `json:"dirty"`
}

// RepoVersion describes one configuration repository.
type RepoVersion struct {
	Path   string `json:"path"`
	Commit string `json:"commit,omitempty"`
	Dirty  bool   `json:"dirty,omitempty"`
	Error  string `json:"error,omitempty"`
}

// Version reports mode, source or build commit, and asset revisions.
func (e *Env) Version(ctx context.Context) VersionReport {
	r := VersionReport{Mode: e.Mode(), Executable: e.Executable, Sources: map[assets.Repo]RepoVersion{}}
	switch src := e.Source.(type) {
	case *assets.Embedded:
		info := src.Info
		r.Build = &info
	case assets.Checkout:
		root := e.gitRevision(ctx, src.Root)
		r.Checkout = &CheckoutVersion{Root: src.Root, Commit: root.Commit, Dirty: root.Dirty}
	}
	for repo, rs := range e.Repos {
		if exists(rs.Dir) {
			r.Sources[repo] = e.gitRevision(ctx, rs.Dir)
		}
	}
	return r
}

func (e *Env) gitRevision(ctx context.Context, dir string) RepoVersion {
	v := RepoVersion{Path: dir}
	commit, err := output(ctx, e.Runner, Cmd{Args: []string{"git", "-C", dir, "rev-parse", "HEAD"}, Env: e.Environ})
	if err != nil {
		v.Error = err.Error()
		return v
	}
	v.Commit = commit
	status, err := output(ctx, e.Runner, Cmd{Args: []string{"git", "-C", dir, "status", "--porcelain"}, Env: e.Environ})
	v.Dirty = err != nil || status != ""
	return v
}

// RenderVersion prints a version report for people.
func RenderVersion(w io.Writer, r VersionReport) {
	switch {
	case r.Build != nil:
		b := r.Build
		fmt.Fprintf(w, "ds main build %s (%s)\n", b.ID, b.Platform)
		fmt.Fprintf(w, "  ds     %s%s\n", b.Commit, dirtyMark(b.Dirty))
		if b.Workflow != nil {
			fmt.Fprintf(w, "  workflow %s\n", b.Workflow.URL)
		}
	case r.Checkout != nil:
		c := r.Checkout
		fmt.Fprintf(w, "ds checkout %s\n", c.Root)
		fmt.Fprintf(w, "  ds     %s%s\n", c.Commit, dirtyMark(c.Dirty))
	}
	for _, repo := range slices.Sorted(maps.Keys(r.Sources)) {
		s := r.Sources[repo]
		if s.Error != "" {
			fmt.Fprintf(w, "  %-6s %s (unavailable)\n", repo, s.Path)
			continue
		}
		fmt.Fprintf(w, "  %-6s %s%s %s\n", repo, s.Commit, dirtyMark(s.Dirty), s.Path)
	}
}

func dirtyMark(dirty bool) string {
	if dirty {
		return " (dirty)"
	}
	return ""
}
