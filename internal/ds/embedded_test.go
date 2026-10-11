package ds

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/letientai299/ds/internal/assets"
	"github.com/letientai299/ds/internal/build"
)

// embeddedBuild snapshots the live ds assets.
func embeddedBuild(t *testing.T) *assets.Embedded {
	t.Helper()
	s, err := build.Collect(context.Background(), build.Options{Root: repoRoot(t)})
	if err != nil {
		t.Fatal(err)
	}
	out := t.TempDir()
	if err := s.WriteEmbedded(out, "darwin/arm64"); err != nil {
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
	exe := filepath.Join(t.TempDir(), "ds-download")
	writeExec(t, exe, "#!/bin/sh\necho ds\n")
	f.env.Executable = exe

	builds := []*assets.Embedded{}
	for i := range 3 {
		emb := embeddedBuild(t)
		emb.Info.ID = fmt.Sprintf("%s-%d", emb.Info.ID, i)
		f.env.Source = emb
		builds = append(builds, emb)
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
	if dest, _ := os.Readlink(cfg["nvim"]); dest != f.env.Repos[assets.Nvim].Dir {
		t.Fatalf("nvim link = %q", dest)
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
