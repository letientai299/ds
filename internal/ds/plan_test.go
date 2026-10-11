package ds

import (
	"context"
	"errors"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/letientai299/ds/internal/assets"
)

var core = LayerRequest{Layers: []LayerName{"core"}}

func TestDryRunWritesNothing(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	before := snapshot(t, f.home)
	p := f.env.BuildPlan(context.Background(), f.state(), core, AddOptions{})
	if len(p.Blockers) > 0 || len(p.Actions) == 0 {
		t.Fatalf("plan: %v blockers %v", actionNames(p), p.Blockers)
	}
	if after := snapshot(t, f.home); !maps.Equal(before, after) {
		t.Fatalf("planning changed the home: %v", after)
	}
	if got := f.logLines("mise install"); len(got) > 0 {
		t.Fatalf("planning installed tools: %v", got)
	}
}

func TestAddConvergesIdempotently(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	f.add(core, AddOptions{})
	cfg := f.env.Target.Placeholders()
	if dest, _ := os.Readlink(filepath.Join(cfg["ds"], "shell.zsh")); !strings.HasSuffix(dest, "assets/dotfiles/shell.zsh") {
		t.Fatalf("shell.zsh -> %s", dest)
	}
	if !strings.Contains(readFile(t, cfg["zshrc"]), `source "`+cfg["ds"]+`/shell.zsh"`) {
		t.Fatal("zshrc lacks the managed block")
	}
	if st := f.state(); !slices.Equal(st.Selection.Layers, []LayerName{"core"}) {
		t.Fatalf("selection = %v", st.Selection)
	}
	again := f.env.BuildPlan(context.Background(), f.state(), core, AddOptions{})
	if len(again.Actions) != 0 {
		t.Fatalf("second plan not empty: %v", actionNames(again))
	}
	if r := f.env.Status(context.Background(), f.state(), nil); !r.Healthy() {
		t.Fatalf("status %s: %+v %+v", r.Summary, r.Components, r.Files)
	}
}

func TestStandaloneComponentGetsDependencies(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	p := f.add(ComponentRequest{Components: []ComponentName{"neovim"}}, AddOptions{})
	if got := joinNames(p.Components, " "); got != "mise git neovim" {
		t.Fatalf("components = %s", got)
	}
	cfg := f.env.Target.Placeholders()
	if _, err := os.Lstat(cfg["nvim"]); err != nil {
		t.Fatal("neovim configuration missing")
	}
	if _, err := os.Lstat(cfg["zshrc"]); err == nil {
		t.Fatal("standalone neovim must not configure zsh")
	}
	if len(f.logLines("nvim --headless")) != 1 {
		t.Fatal("neovim plugins were not bootstrapped")
	}
}

func TestSelectionIsAdditive(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	f.add(LayerRequest{Layers: []LayerName{"extra"}}, AddOptions{})
	f.add(ComponentRequest{Components: []ComponentName{"tmux"}}, AddOptions{})
	st := f.state()
	if st.Selection.String() != "-l extra tmux" {
		t.Fatalf("selection = %s", st.Selection)
	}
	fragment := readFile(t, fragmentPath(f.env.Target))
	if !strings.Contains(fragment, "bat") || !strings.Contains(fragment, "http:delta") {
		t.Fatalf("fragment lost extra tools:\n%s", fragment)
	}
}

func TestUserMisePinsSurvive(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	user := filepath.Join(f.env.Target.MiseConfigDir(), "config.toml")
	writeFile(t, user, "[tools]\nfd = \"9.0.0\"\n")
	f.add(core, AddOptions{})
	if got := readFile(t, user); got != "[tools]\nfd = \"9.0.0\"\n" {
		t.Fatalf("user config changed: %q", got)
	}
}

func TestConflictNeedsForceAndKeepsBackup(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	cfg := f.env.Target.Placeholders()
	foreign := filepath.Join(cfg["ds"], "shell.zsh")
	writeFile(t, foreign, "mine\n")
	writeFile(t, cfg["zshrc"], "export KEEP=1\n")

	p := f.env.BuildPlan(context.Background(), f.state(), core, AddOptions{})
	if len(p.Blockers) != 1 || p.Blockers[0].Subject != foreign {
		t.Fatalf("blockers = %v", p.Blockers)
	}
	st := f.state()
	var blocked *BlockedError
	if err := f.env.Execute(context.Background(), p, &st, "add"); !errors.As(err, &blocked) {
		t.Fatalf("blocked plan executed: %v", err)
	}
	if _, err := os.Lstat(cfg["bin"] + "/ds"); err == nil {
		t.Fatal("blocked plan made changes")
	}

	p = f.add(core, AddOptions{Force: true})
	var backup string
	for _, a := range p.Actions {
		if fc, ok := a.(FileChange); ok && fc.Entry.path() == foreign {
			backup = fc.Backup
		}
	}
	if backup == "" || readFile(t, backup) != "mine\n" {
		t.Fatalf("backup %q missing original content", backup)
	}
	if !strings.HasPrefix(readFile(t, cfg["zshrc"]), "export KEEP=1\n") {
		t.Fatal("user rc content lost")
	}
}

func TestInstallerLinksAreOwned(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	cfg := f.env.Target.Placeholders()
	old := filepath.Join(f.env.Target.Paths().Data, "ds-source", "ds", "src", "dotfiles", "shell.zsh")
	writeFile(t, old, "old\n")
	mustMkdir(t, cfg["ds"])
	symlink(t, old, filepath.Join(cfg["ds"], "shell.zsh"))
	p := f.env.BuildPlan(context.Background(), f.state(), core, AddOptions{})
	if len(p.Blockers) != 0 {
		t.Fatalf("blockers = %v", p.Blockers)
	}
}

func TestCheckoutReusesBuildSnapshot(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	paths := f.env.Target.Paths()
	src := f.env.Source.(assets.Checkout)
	lone := filepath.Join(t.TempDir(), "ds")
	cfg := UserConfig{Sources: map[string]string{"tmux": src.Repos[assets.Tmux]}}

	repos, err := cfg.CheckoutRepos(lone, paths)
	if err != nil || repos[assets.Nvim] != filepath.Join(filepath.Dir(lone), "nvim.conf") {
		t.Fatalf("without snapshot: %v %v", repos, err)
	}
	for _, repo := range []assets.Repo{assets.Nvim, assets.Kitty} {
		writeFile(t, filepath.Join(buildSnapshot(paths, repo), "README"), "snapshot\n")
	}
	writeExec(t, filepath.Join(buildSnapshot(paths, assets.Kitty), "bin", "kt"), fakeCommand)
	if repos, err = cfg.CheckoutRepos(lone, paths); err != nil {
		t.Fatal(err)
	}
	if repos[assets.Nvim] != buildSnapshot(paths, assets.Nvim) || repos[assets.Tmux] != src.Repos[assets.Tmux] {
		t.Fatalf("repos = %v", repos)
	}

	f.env.Source = assets.Checkout{Root: src.Root, Repos: repos}
	p := f.env.BuildPlan(context.Background(), f.state(), LayerRequest{Layers: []LayerName{"core", "ui"}}, AddOptions{})
	if len(p.Blockers) != 0 || !hasAction(p, "-> "+buildSnapshot(paths, assets.Nvim)) {
		t.Fatalf("actions = %v, blockers = %v", actionNames(p), p.Blockers)
	}
	if slices.ContainsFunc(p.Actions, func(a Action) bool { _, ok := a.(BuildHelper); return ok }) {
		t.Fatal("rebuilds the snapshot helper")
	}
	notes := strings.Join(p.Notes, "\n")
	if !strings.Contains(notes, "nvim: using the installed build's snapshot") || !strings.Contains(notes, "kitty:") || strings.Contains(notes, "tmux:") {
		t.Fatalf("notes = %v", p.Notes)
	}
}

func TestBackupsAreNeverOverwritten(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	cfg := f.env.Target.Placeholders()
	foreign := filepath.Join(cfg["ds"], "shell.zsh")
	writeFile(t, foreign, "mine\n")
	p := f.env.BuildPlan(context.Background(), f.state(), core, AddOptions{Force: true})
	for _, a := range p.Actions {
		if fc, ok := a.(FileChange); ok && fc.Backup != "" {
			writeFile(t, fc.Backup, "earlier backup\n")
		}
	}
	st := f.state()
	if err := f.env.Execute(context.Background(), p, &st, "add"); err == nil || !strings.Contains(err.Error(), "backup already exists") {
		t.Fatalf("err = %v", err)
	}
	if readFile(t, foreign) != "mine\n" {
		t.Fatal("conflicting file replaced without a backup")
	}
}

func TestSymlinkedRcStaysBlocked(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	cfg := f.env.Target.Placeholders()
	real := filepath.Join(f.home, "dotfiles", "zshrc")
	writeFile(t, real, "x\n")
	if err := os.Symlink(real, cfg["zshrc"]); err != nil {
		t.Fatal(err)
	}
	p := f.env.BuildPlan(context.Background(), f.state(), core, AddOptions{Force: true})
	if len(p.Blockers) != 1 || p.Blockers[0].Subject != cfg["zshrc"] {
		t.Fatalf("blockers = %v", p.Blockers)
	}
}

func TestNoPackagesRequiresCommands(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	os.Remove(filepath.Join(f.tools, "tmux"))
	p := f.env.BuildPlan(context.Background(), f.state(), core, AddOptions{NoPackages: true})
	if len(p.Blockers) != 1 || p.Blockers[0].Subject != "tmux" {
		t.Fatalf("blockers = %v", p.Blockers)
	}
	p = f.env.BuildPlan(context.Background(), f.state(), core, AddOptions{})
	if !slices.ContainsFunc(p.Blockers, func(b Blocker) bool { return b.Reason == "no supported package manager" }) {
		t.Fatalf("missing Homebrew must block: %v", p.Blockers)
	}
	writeExec(t, filepath.Join(f.tools, "brew"), fakeCommand)
	p = f.env.BuildPlan(context.Background(), f.state(), core, AddOptions{})
	if !hasAction(p, "install brew packages: tmux") {
		t.Fatalf("actions = %v", actionNames(p))
	}
}

func TestLinuxPackagesNeedPrivilege(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	f.env.Platform = Platform{OS: "linux", Arch: "amd64", Libc: "glibc", Glibc: "2.39"}
	os.Remove(filepath.Join(f.tools, "tmux"))
	writeExec(t, filepath.Join(f.tools, "apt-get"), fakeCommand)
	writeExec(t, filepath.Join(f.tools, "sudo"), "#!/bin/sh\nexit 1\n")
	p := f.env.BuildPlan(context.Background(), f.state(), core, AddOptions{})
	if !slices.ContainsFunc(p.Blockers, func(b Blocker) bool { return strings.Contains(b.Reason, "passwordless sudo") }) {
		t.Fatalf("blockers = %v", p.Blockers)
	}
	f.env.UID = 0
	p = f.env.BuildPlan(context.Background(), f.state(), core, AddOptions{})
	if len(p.Blockers) > 0 || !hasAction(p, "install apt packages: file tmux") || hasAction(p, "with sudo") {
		t.Fatalf("root plan %v blockers %v", actionNames(p), p.Blockers)
	}
}

func TestKittyNeedsGlibc(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	f.env.Platform = Platform{OS: "linux", Arch: "arm64", Libc: "glibc", Glibc: "2.34"}
	p := f.env.BuildPlan(context.Background(), f.state(), LayerRequest{Layers: []LayerName{"ui"}}, AddOptions{})
	if !slices.ContainsFunc(p.Blockers, func(b Blocker) bool { return b.Subject == "kitty" }) {
		t.Fatalf("blockers = %v", p.Blockers)
	}
}

func TestMuslIsUnsupported(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	f.env.Platform = Platform{OS: "linux", Arch: "amd64", Libc: "musl"}
	p := f.env.BuildPlan(context.Background(), f.state(), core, AddOptions{})
	if len(p.Blockers) != 1 || p.Blockers[0].Subject != "platform" || len(p.Actions) != 0 {
		t.Fatalf("blockers = %v, actions = %v", p.Blockers, actionNames(p))
	}
	if r := f.env.Status(context.Background(), f.state(), core); r.Healthy() {
		t.Fatal("status healthy on musl")
	}
}

func TestLegacyMiseConfigIsNoted(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	target := f.env.Target.(HomeTarget)
	target.P.MiseConfig = filepath.Join(target.P.Config, "ds", "mise")
	f.env.Target = target
	p := f.env.BuildPlan(context.Background(), f.state(), core, AddOptions{})
	if !slices.ContainsFunc(p.Notes, func(n string) bool { return strings.HasPrefix(n, "MISE_CONFIG_DIR is the old") }) {
		t.Fatalf("notes = %v", p.Notes)
	}
}

func TestExplicitHomeIgnoresInheritedPaths(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	elsewhere := t.TempDir()
	env := map[string]string{"HOME": elsewhere, "XDG_CONFIG_HOME": elsewhere, "MISE_CONFIG_DIR": elsewhere}
	paths, err := ResolvePaths(func(k string) string { return env[k] }, f.home)
	if err != nil {
		t.Fatal(err)
	}
	f.env.Target = HomeTarget{P: paths}
	f.env.Environ = f.env.Environ.with("XDG_CONFIG_HOME", elsewhere, "MISE_CONFIG_DIR", elsewhere)
	f.add(core, AddOptions{})
	if entries, _ := os.ReadDir(elsewhere); len(entries) != 0 {
		t.Fatalf("wrote outside the explicit home: %v", entries)
	}
}

// Sequential: a child forked by a parallel test holds the descriptor until
// it execs, delaying release.
func TestLockIsExclusive(t *testing.T) {
	f := newFixture(t)
	l, err := AcquireLock(f.env.Target)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := AcquireLock(f.env.Target); err == nil || !strings.Contains(err.Error(), "another ds operation") {
		t.Fatalf("second lock: %v", err)
	}
	l.Close()
	l2, err := AcquireLock(f.env.Target)
	if err != nil {
		t.Fatalf("lock after release: %v", err)
	}
	l2.Close()
}

func TestFailureRecordsProgress(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	writeExec(t, filepath.Join(f.tools, "mise"), strings.Replace(fakeMise, "install)\n", "install)\n\texit 7\n", 1))
	st := f.state()
	p := f.env.BuildPlan(context.Background(), st, core, AddOptions{})
	err := f.env.Execute(context.Background(), p, &st, "add")
	var partial *PartialError
	if !errors.As(err, &partial) || !strings.HasPrefix(partial.Failed, "install mise tools") || len(partial.Completed) == 0 {
		t.Fatalf("err = %v", err)
	}
	if !strings.Contains(readFile(t, partial.Record), `"failed": "install mise tools`) {
		t.Fatal("operation record lacks the failure")
	}
	if !f.state().Selection.Empty() {
		t.Fatal("selection saved despite failure")
	}
	writeExec(t, filepath.Join(f.tools, "mise"), fakeMise)
	retry := f.add(core, AddOptions{})
	if !hasAction(retry, "install mise tools") || hasAction(retry, "create link") {
		t.Fatalf("retry must resume from observed state: %v", actionNames(retry))
	}
}

func TestOwnershipRecheckedAtMutation(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	st := f.state()
	p := f.env.BuildPlan(context.Background(), st, core, AddOptions{})
	writeFile(t, filepath.Join(f.env.Target.Placeholders()["ds"], "shell.zsh"), "raced\n")
	err := f.env.Execute(context.Background(), p, &st, "add")
	if err == nil || !strings.Contains(err.Error(), "changed since planning") {
		t.Fatalf("err = %v", err)
	}
}

func TestTrialIsolation(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	writeFile(t, filepath.Join(f.home, ".gitconfig"), "[user]\n\tname = Me\n")
	home := snapshot(t, f.home)
	f.env.Target = TrialTarget{P: f.env.Target.Paths()}
	env, err := f.env.PrepareTrial(context.Background(), State{})
	if err != nil {
		t.Fatalf("%v\n%s", err, f.err.String())
	}
	trial := f.env.Target.(TrialTarget)
	for p, v := range snapshot(t, f.home) {
		if _, ok := home[p]; ok || within(p, trial.Root()) {
			continue
		}
		if !within(p, filepath.Join(f.home, ".config", "ds-trial-nvim")) && !within(p, filepath.Dir(trial.Root())) &&
			p != filepath.Join(f.home, ".config") && p != filepath.Join(f.home, ".local") &&
			p != filepath.Join(f.home, ".local", "state") {
			t.Errorf("trial wrote outside its namespace: %s = %s", p, v)
		}
	}
	if !strings.Contains(readFile(t, trial.GitConfig()), filepath.Join(f.home, ".gitconfig")) {
		t.Fatal("trial Git config lacks the base identity")
	}
	for _, want := range []string{"ZDOTDIR=" + trial.ZDotDir(), "GIT_CONFIG_GLOBAL=" + trial.GitConfig(), "NVIM_APPNAME=ds-trial-nvim"} {
		if !slices.Contains(env, want) {
			t.Errorf("trial env lacks %s", want)
		}
	}
	if slices.ContainsFunc(env, func(kv string) bool { return strings.HasPrefix(kv, "HOME=") && kv != "HOME="+f.home }) {
		t.Error("trial changed HOME")
	}
	if len(f.logLines("mise install")) > 0 || len(f.logLines("mise bootstrap")) > 0 {
		t.Fatal("trial creation installed tools or packages")
	}
	wrapper := readFile(t, filepath.Join(trial.Bin(), "tmux"))
	if !strings.Contains(wrapper, "-L ds-trial") {
		t.Fatal("trial tmux lacks its own server")
	}
}
