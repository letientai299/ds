// Command ds-build exports configuration snapshots and builds main-mode
// binaries for CI.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/letientai299/ds/internal/assets"
	"github.com/letientai299/ds/internal/build"
)

const usage = `usage:
  ds-build dist [--out DIR] [--source REPO=DIR]... [--platform OS/ARCH]...
  ds-build check-static FILE...`

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, usage)
		os.Exit(2)
	}
	ctx := context.Background()
	var err error
	switch os.Args[1] {
	case "dist":
		err = dist(ctx, os.Args[2:])
	case "check-static":
		for _, p := range os.Args[2:] {
			if err = build.CheckStatic(p); err != nil {
				break
			}
		}
	default:
		fmt.Fprintln(os.Stderr, usage)
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "ds-build: %v\n", err)
		os.Exit(1)
	}
}

type repeated []string

func (r *repeated) String() string     { return strings.Join(*r, ",") }
func (r *repeated) Set(v string) error { *r = append(*r, v); return nil }

func dist(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("dist", flag.ContinueOnError)
	out := fs.String("out", "dist", "output directory")
	var sources, platforms repeated
	fs.Var(&sources, "source", "configuration checkout as REPO=DIR (default: sibling REPO.conf)")
	fs.Var(&platforms, "platform", "target OS/ARCH (default: all)")
	if err := fs.Parse(args); err != nil {
		return err
	}
	root, err := os.Getwd()
	if err != nil {
		return err
	}
	opt := build.Options{Root: root, Sources: map[assets.Repo]string{}, Workflow: build.WorkflowFromEnv(os.Getenv)}
	for _, repo := range assets.ConfigRepos {
		opt.Sources[repo] = filepath.Join(filepath.Dir(root), repo.CheckoutName())
	}
	for _, s := range sources {
		name, dir, ok := strings.Cut(s, "=")
		if !ok || !assets.Repo(name).Valid() || assets.Repo(name) == assets.DS {
			return fmt.Errorf("invalid --source %q", s)
		}
		if opt.Sources[assets.Repo(name)], err = filepath.Abs(dir); err != nil {
			return err
		}
	}
	if len(platforms) == 0 {
		platforms = build.Platforms
	}
	m, err := build.Dist(ctx, opt, *out, platforms)
	if err != nil {
		return err
	}
	fmt.Printf("build %s\n", m.Build)
	return nil
}
