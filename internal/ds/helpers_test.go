package ds

import (
	"bytes"
	"context"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/letientai299/ds/internal/assets"
)

// repoRoot is the ds checkout holding these tests.
func repoRoot(t *testing.T) string {
	t.Helper()
	_, file, _, _ := runtime.Caller(0)
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", ".."))
}

// fakeMise records installs and reports them through `ls --json`.
const fakeMise = `#!/bin/sh
log=${DS_TEST_LOG:?}
printf 'mise %s\n' "$*" >>"$log"
while [ "$#" -gt 0 ]; do
	case "$1" in
	-C) shift 2 ;;
	*) break ;;
	esac
done
state=$MISE_DATA_DIR/fake
case "$1" in
--version) echo '2026.9.12 test' ;;
install)
	shift
	mkdir -p "$state"
	for tool in "$@"; do : >"$state/$(printf %s "$tool" | tr :/ -_)"; done
	;;
ls)
	printf '{'
	sep=
	conf=$MISE_CONFIG_DIR/conf.d/10-ds.toml
	for f in "$state"/*; do
		[ -e "$f" ] || continue
		name=$(basename "$f" | sed 's/^http-/http:/; s/^npm-/npm:/; s/^aqua-/aqua:/; s|_|/|g')
		printf '%s"%s":[{"version":"1.0.0","requested_version":"latest","installed":true,"source":{"path":"%s"}}]' "$sep" "$name" "$conf"
		sep=,
	done
	printf '}\n'
	;;
upgrade | bootstrap | exec) ;;
*) echo "fake mise: unsupported $*" >&2; exit 1 ;;
esac
`

// fakeNvim marks plugin bootstrap complete.
const fakeNvim = `#!/bin/sh
printf 'nvim %s\n' "$*" >>"${DS_TEST_LOG:?}"
mkdir -p "$XDG_DATA_HOME/${NVIM_APPNAME:-nvim}/lazy/lazy.nvim"
`

const fakeCommand = "#!/bin/sh\nexit 0\n"

type fixture struct {
	t     *testing.T
	home  string
	tools string // directory with fake system commands
	log   string
	env   *Env
	err   bytes.Buffer
}

// newFixture builds an Env over a temporary home using the live checkout
// assets and fake configuration repositories.
func newFixture(t *testing.T) *fixture {
	t.Helper()
	dir := t.TempDir()
	f := &fixture{t: t, home: filepath.Join(dir, "home"), tools: filepath.Join(dir, "tools"), log: filepath.Join(dir, "log")}
	mustMkdir(t, f.home)
	sys := filepath.Join(dir, "sys")
	mustMkdir(t, sys)
	for _, util := range []string{"sh", "mkdir", "tr", "sed", "basename", "cat", "rm", "dirname", "wc", "chmod", "mktemp"} {
		if real, err := exec.LookPath(util); err == nil {
			symlink(t, real, filepath.Join(sys, util))
		}
	}
	writeExec(t, filepath.Join(f.tools, "mise"), fakeMise)
	writeExec(t, filepath.Join(f.tools, "nvim"), fakeNvim)
	for _, cmd := range []string{"git", "curl", "zsh", "tmux", "kitty", "kitten", "cc", "make"} {
		writeExec(t, filepath.Join(f.tools, cmd), fakeCommand)
	}
	repos := map[assets.Repo]string{}
	for _, repo := range assets.ConfigRepos {
		p := filepath.Join(dir, repo.CheckoutName())
		writeFile(t, filepath.Join(p, "README"), "fixture\n")
		repos[repo] = p
	}
	writeExec(t, filepath.Join(repos[assets.Tmux], "tm"), fakeCommand)
	writeExec(t, filepath.Join(repos[assets.Kitty], "bin", "kt"), fakeCommand)
	paths, err := ResolvePaths(func(string) string { return "" }, f.home)
	if err != nil {
		t.Fatal(err)
	}
	src := assets.Checkout{Root: repoRoot(t)}
	cat, err := LoadCatalog(src)
	if err != nil {
		t.Fatal(err)
	}
	sources := map[assets.Repo]RepoSource{}
	for repo, dir := range repos {
		sources[repo] = RepoSource{Dir: dir, URL: cat.RepoURL(repo)}
	}
	f.env = &Env{
		Target:   HomeTarget{P: paths},
		Source:   src,
		Repos:    sources,
		Catalog:  cat,
		Platform: Platform{OS: "darwin", Arch: "arm64"},
		Runner:   ExecRunner{},
		Environ: envList{
			"PATH=" + f.tools + ":" + sys,
			"DS_TEST_LOG=" + f.log,
		},
		Stdout:     &f.err,
		Stderr:     &f.err,
		UID:        501,
		Now:        func() time.Time { return time.Date(2026, 10, 11, 12, 0, 0, 0, time.UTC) },
		Mise:       DefaultMise,
		Completion: []byte("#compdef ds\n"),
	}
	return f
}

func (f *fixture) state() State {
	f.t.Helper()
	st, err := LoadState(f.env.Target)
	if err != nil {
		f.t.Fatal(err)
	}
	return st
}

// add plans and executes like `ds add`.
func (f *fixture) add(req Request, opt AddOptions) *Plan {
	f.t.Helper()
	st := f.state()
	p := f.env.BuildPlan(context.Background(), st, req, opt)
	if err := f.env.Execute(context.Background(), p, &st, "add"); err != nil {
		f.t.Fatalf("execute: %v\noutput:\n%s", err, f.err.String())
	}
	return p
}

func (f *fixture) logLines(prefix string) []string {
	data, _ := os.ReadFile(f.log)
	var out []string
	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(line, prefix) {
			out = append(out, line)
		}
	}
	return out
}

// snapshot records every path and its content under root.
func snapshot(t *testing.T, root string) map[string]string {
	t.Helper()
	out := map[string]string{}
	err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		info, _ := d.Info()
		switch {
		case info.Mode()&fs.ModeSymlink != 0:
			dest, _ := os.Readlink(p)
			out[p] = "-> " + dest
		case info.Mode().IsRegular():
			data, _ := os.ReadFile(p)
			out[p] = string(data)
		default:
			out[p] = "dir"
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func actionNames(p *Plan) []string {
	var out []string
	for _, a := range p.Actions {
		out = append(out, a.Describe())
	}
	return out
}

func hasAction(p *Plan, substr string) bool {
	return slices.ContainsFunc(actionNames(p), func(s string) bool { return strings.Contains(s, substr) })
}

func mustMkdir(t *testing.T, p string) {
	t.Helper()
	if err := os.MkdirAll(p, 0o755); err != nil {
		t.Fatal(err)
	}
}

func writeFile(t *testing.T, p, content string) {
	t.Helper()
	mustMkdir(t, filepath.Dir(p))
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func writeExec(t *testing.T, p, content string) {
	t.Helper()
	mustMkdir(t, filepath.Dir(p))
	if err := os.WriteFile(p, []byte(content), 0o755); err != nil {
		t.Fatal(err)
	}
}

func readFile(t *testing.T, p string) string {
	t.Helper()
	data, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}
