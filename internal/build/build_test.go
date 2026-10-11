package build

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/letientai299/ds/internal/assets"
)

func run(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@example.invalid",
		"GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@example.invalid")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("%v: %v\n%s", args, err, out)
	}
}

func write(t *testing.T, p, content string, mode os.FileMode) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(content), mode); err != nil {
		t.Fatal(err)
	}
}

func repo(t *testing.T, dir string, files map[string]string) string {
	t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	run(t, dir, "git", "init", "-q")
	for name, content := range files {
		mode := os.FileMode(0o644)
		if strings.HasSuffix(name, ".sh") {
			mode = 0o755
		}
		write(t, filepath.Join(dir, name), content, mode)
	}
	run(t, dir, "git", "add", ".")
	run(t, dir, "git", "commit", "-qm", "init")
	return dir
}

func fixtureOptions(t *testing.T) Options {
	dir := t.TempDir()
	root := repo(t, filepath.Join(dir, "ds"), map[string]string{
		"assets/catalog.toml":        "x",
		"assets/dotfiles/.hidden":    "h",
		"assets/tools/run.sh":        "#!/bin/sh\n",
		"assets/_underscore/file":    "u",
		"cmd/ds/main.go":             "package main\n",
		"assets/dotfiles/.gitignore": "ignored.txt\n",
	})
	write(t, filepath.Join(root, "assets/dotfiles/ignored.txt"), "no", 0o644)
	write(t, filepath.Join(root, "assets/dotfiles/untracked"), "yes", 0o644)
	if err := os.Symlink(".hidden", filepath.Join(root, "assets/dotfiles/link")); err != nil {
		t.Fatal(err)
	}
	return Options{Root: root}
}

func TestSnapshotRoundTrip(t *testing.T) {
	opt := fixtureOptions(t)
	s, err := Collect(context.Background(), opt)
	if err != nil {
		t.Fatal(err)
	}
	out := t.TempDir()
	if err := s.WriteEmbedded(out, "linux/amd64"); err != nil {
		t.Fatal(err)
	}
	meta, _ := os.ReadFile(filepath.Join(out, "build.json"))
	archive, _ := os.ReadFile(filepath.Join(out, "assets.tar.gz"))
	emb, err := assets.NewEmbedded(meta, archive)
	if err != nil {
		t.Fatal(err)
	}
	if !s.Info.Dirty {
		t.Fatal("untracked asset not marked dirty")
	}
	dest := filepath.Join(t.TempDir(), "assets")
	if err := emb.Extract(dest); err != nil {
		t.Fatal(err)
	}
	checks := []struct {
		path string
		mode os.FileMode
	}{
		{"ds/catalog.toml", 0o644},
		{"ds/dotfiles/.hidden", 0o644},
		{"ds/_underscore/file", 0o644},
		{"ds/dotfiles/untracked", 0o644},
		{"ds/tools/run.sh", 0o755},
	}
	for _, c := range checks {
		info, err := os.Stat(filepath.Join(dest, c.path))
		if err != nil {
			t.Errorf("%s: %v", c.path, err)
			continue
		}
		if info.Mode().Perm() != c.mode {
			t.Errorf("%s mode %v, want %v", c.path, info.Mode().Perm(), c.mode)
		}
	}
	for _, absent := range []string{"ds/dotfiles/ignored.txt", "ds/cmd/ds/main.go"} {
		if _, err := os.Lstat(filepath.Join(dest, absent)); err == nil {
			t.Errorf("%s must not be exported", absent)
		}
	}
	if link, err := os.Readlink(filepath.Join(dest, "ds", "dotfiles", "link")); err != nil || link != ".hidden" {
		t.Errorf("symlink = %q, %v", link, err)
	}
	if data, err := emb.ReadFile(assets.Ref{Repo: assets.DS, Path: "catalog.toml"}); err != nil || string(data) != "x" {
		t.Errorf("ReadFile = %q, %v", data, err)
	}
}

func TestBuildIDTracksSources(t *testing.T) {
	opt := fixtureOptions(t)
	first, err := Collect(context.Background(), opt)
	if err != nil {
		t.Fatal(err)
	}
	again, _ := Collect(context.Background(), opt)
	if first.Info.ID != again.Info.ID {
		t.Fatal("build ID is not deterministic")
	}
	write(t, filepath.Join(opt.Root, "cmd/ds/main.go"), "package main // changed\n", 0o644)
	changed, _ := Collect(context.Background(), opt)
	if changed.Info.ID == first.Info.ID {
		t.Fatal("code change kept the build ID")
	}
	a, _ := tarball(first.entries)
	b, _ := tarball(again.entries)
	if string(a) != string(b) {
		t.Fatal("archive is not deterministic")
	}
}

func TestSymlinkEscapeRejected(t *testing.T) {
	opt := fixtureOptions(t)
	if err := os.Symlink("../../../etc/passwd", filepath.Join(opt.Root, "assets", "escape")); err != nil {
		t.Fatal(err)
	}
	if _, err := Collect(context.Background(), opt); err == nil || !strings.Contains(err.Error(), "outside its repository") {
		t.Fatalf("err = %v", err)
	}
}
