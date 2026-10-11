package ds

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/letientai299/ds/internal/assets"
	"github.com/letientai299/ds/internal/build"
)

// embeddedBuild snapshots the live assets and the fixture repositories.
func embeddedBuild(t *testing.T, repos map[assets.Repo]string) *assets.Embedded {
	t.Helper()
	for _, repo := range assets.ConfigRepos {
		dir := repos[repo]
		if _, err := os.Stat(filepath.Join(dir, ".git")); err != nil {
			git(t, dir, "init", "-q")
		}
		git(t, dir, "add", "-A")
		git(t, dir, "commit", "-qm", "snapshot", "--allow-empty")
	}
	s, err := build.Collect(context.Background(), build.Options{Root: repoRoot(t), Sources: repos})
	if err != nil {
		t.Fatal(err)
	}
	out := t.TempDir()
	if err := s.WriteEmbedded(out, "darwin/arm64", []byte("#!/bin/sh\n")); err != nil {
		t.Fatal(err)
	}
	meta, _ := os.ReadFile(filepath.Join(out, "build.json"))
	archive, _ := os.ReadFile(filepath.Join(out, "assets.tar.gz"))
	emb, err := assets.NewEmbedded(meta, archive)
	if err != nil {
		t.Fatal(err)
	}
	return emb
}

func TestMainBuildStagesAndActivates(t *testing.T) {
	t.Parallel()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git required")
	}
	f := newFixture(t)
	repos := f.env.Source.(assets.Checkout).Repos
	exe := filepath.Join(t.TempDir(), "ds-download")
	writeExec(t, exe, "#!/bin/sh\necho ds\n")
	f.env.Executable = exe

	builds := []*assets.Embedded{}
	for i := range 3 {
		writeFile(t, filepath.Join(repos[assets.Nvim], "init.lua"), strings.Repeat("-- v\n", i+1))
		f.env.Source = embeddedBuild(t, repos)
		builds = append(builds, f.env.Source.(*assets.Embedded))
		p := f.add(core, AddOptions{})
		if !hasAction(p, "stage build") || !hasAction(p, "activate build") {
			t.Fatalf("build %d actions: %v", i, actionNames(p))
		}
	}
	data := f.env.Target.Paths().DSData()
	last, previous := builds[2].Info.ID, builds[1].Info.ID
	if currentBuild(data) != last {
		t.Fatalf("current = %s", currentBuild(data))
	}
	entries, _ := os.ReadDir(filepath.Join(data, "builds"))
	var names []string
	for _, e := range entries {
		names = append(names, e.Name())
	}
	if strings.Join(names, ",") != strings.Join(sortedUnique([]string{last, previous}), ",") {
		t.Fatalf("builds kept = %v", names)
	}
	cfg := f.env.Target.Placeholders()
	if got := readFile(t, filepath.Join(cfg["nvim"], "init.lua")); got != strings.Repeat("-- v\n", 3) {
		t.Fatalf("nvim config through current = %q", got)
	}
	if got := readFile(t, filepath.Join(cfg["bin"], "ds")); got != "#!/bin/sh\necho ds\n" {
		t.Fatalf("ds link target = %q", got)
	}
	if info, _ := os.Stat(filepath.Join(data, "current", "assets", "ds", "tools", "fzf-files")); info.Mode().Perm()&0o111 == 0 {
		t.Fatal("executable mode lost")
	}
	if again := f.env.BuildPlan(context.Background(), f.state(), core, AddOptions{}); len(again.Actions) != 0 {
		t.Fatalf("converged main build not idempotent: %v", actionNames(again))
	}
}
