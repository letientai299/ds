package ds

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/pelletier/go-toml/v2"
)

func TestPrepareDirenv(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		shared string
		local  string
		want   string
	}{
		{name: "no shared config", want: "mise.local.toml"},
		{name: "root config", shared: "mise.toml", want: "mise.local.toml"},
		{name: "hidden root config", shared: ".mise.toml", want: ".mise.local.toml"},
		{name: "mise directory", shared: "mise/config.toml", want: "mise/config.local.toml"},
		{name: "hidden mise directory", shared: ".mise/config.toml", want: ".mise/config.local.toml"},
		{name: "config directory", shared: ".config/mise.toml", want: ".config/mise.local.toml"},
		{name: "config mise filename", shared: ".config/mise/mise.toml", want: ".config/mise/mise.local.toml"},
		{name: "config mise directory", shared: ".config/mise/config.toml", want: ".config/mise/config.local.toml"},
		{name: "existing local", local: "mise.local.toml", want: "mise.local.toml"},
		{name: "existing hidden local", local: ".mise.local.toml", want: ".mise.local.toml"},
		{name: "existing nested local", local: ".config/mise/config.local.toml", want: ".config/mise/config.local.toml"},
		{name: "existing local wins", shared: "mise.toml", local: ".config/mise.local.toml", want: ".config/mise.local.toml"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			root := t.TempDir()
			git(t, root, "init", "-q")
			const shared = "[tools]\nnode = '22'\n"
			const local = "[env]\nEXISTING = 'preserve me'\n"
			if tt.shared != "" {
				writeFile(t, filepath.Join(root, tt.shared), shared)
			}
			if tt.local != "" {
				writeFile(t, filepath.Join(root, tt.local), local)
			}
			dir := filepath.Join(root, "src", "nested")
			mustMkdir(t, dir)
			writeFile(t, filepath.Join(dir, "mise.toml"), "[env]\nNESTED = 'ignored'\n")
			path, err := PrepareDirenv(context.Background(), ExecRunner{}, os.Environ(), dir)
			want := filepath.Join(git(t, root, "rev-parse", "--show-toplevel"), tt.want)
			if err != nil || path != want {
				t.Fatalf("path = %q, err = %v, want %q", path, err, want)
			}
			data := readFile(t, path)
			if tt.local != "" && data != local {
				t.Fatalf("local config changed: %q", data)
			}
			if tt.shared != "" && readFile(t, filepath.Join(root, tt.shared)) != shared {
				t.Fatal("shared config changed")
			}
			var config map[string]any
			if err := toml.Unmarshal([]byte(data), &config); err != nil {
				t.Fatalf("invalid local config: %v", err)
			}
			if tt.local == "" {
				for key, value := range config {
					section, ok := value.(map[string]any)
					if !ok || len(section) != 0 {
						t.Fatalf("template enables configuration: %s = %v", key, value)
					}
				}
				info, err := os.Stat(path)
				if err != nil || info.Mode().Perm() != 0o600 {
					t.Fatalf("config permissions: info = %v, err = %v", info, err)
				}
			}
			if again, err := PrepareDirenv(context.Background(), ExecRunner{}, os.Environ(), dir); err != nil || again != path || readFile(t, path) != data {
				t.Fatalf("repeat changed config: path = %q, err = %v", again, err)
			}
		})
	}
}

func TestDirenvTemplateExamples(t *testing.T) {
	t.Parallel()
	examples := strings.ReplaceAll(direnvTemplate, "\n# ", "\n")
	var config map[string]any
	if err := toml.Unmarshal([]byte(examples), &config); err != nil {
		t.Fatalf("uncommented examples are invalid: %v", err)
	}
}

func TestDirenvNonDirectoryLayouts(t *testing.T) {
	t.Parallel()
	for _, name := range []string{"mise", ".mise", ".config"} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			root := t.TempDir()
			git(t, root, "init", "-q")
			writeFile(t, filepath.Join(root, name), "project file\n")
			writeFile(t, filepath.Join(root, "mise.toml"), "[env]\n")
			path, err := PrepareDirenv(context.Background(), ExecRunner{}, os.Environ(), root)
			want := filepath.Join(git(t, root, "rev-parse", "--show-toplevel"), "mise.local.toml")
			if err != nil || path != want {
				t.Fatalf("path = %q, err = %v, want %q", path, err, want)
			}
		})
	}
}

func TestDirenvRootWhitespace(t *testing.T) {
	t.Parallel()
	for _, suffix := range []string{" ", "\n"} {
		t.Run(suffix, func(t *testing.T) {
			t.Parallel()
			root := filepath.Join(t.TempDir(), "project"+suffix)
			mustMkdir(t, root)
			git(t, root, "init", "-q")
			realRoot, err := filepath.EvalSymlinks(root)
			if err != nil {
				t.Fatal(err)
			}
			path, err := PrepareDirenv(context.Background(), ExecRunner{}, os.Environ(), root)
			want := filepath.Join(realRoot, "mise.local.toml")
			if err != nil || path != want {
				t.Fatalf("path = %q, err = %v, want %q", path, err, want)
			}
		})
	}
}

func TestDirenvConfigPrecedence(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "mise.toml"), "")
	writeFile(t, filepath.Join(root, ".mise.toml"), "")
	writeFile(t, filepath.Join(root, ".config/mise.toml"), "")
	path, err := localMisePath(root)
	if want := filepath.Join(root, ".mise.local.toml"); err != nil || path != want {
		t.Fatalf("path = %q, err = %v, want %q", path, err, want)
	}
}

func TestDirenvWorktree(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	git(t, root, "init", "-q")
	writeFile(t, filepath.Join(root, ".config/mise/config.toml"), "[env]\n")
	git(t, root, "add", ".config/mise/config.toml")
	git(t, root, "commit", "-qm", "initial")
	worktree := filepath.Join(t.TempDir(), "linked worktree")
	git(t, root, "worktree", "add", "-qb", "topic", worktree)
	path, err := PrepareDirenv(context.Background(), ExecRunner{}, os.Environ(), worktree)
	want := filepath.Join(git(t, worktree, "rev-parse", "--show-toplevel"), ".config/mise/config.local.toml")
	if err != nil || path != want {
		t.Fatalf("path = %q, err = %v, want %q", path, err, want)
	}
	if exists(filepath.Join(root, ".config/mise/config.local.toml")) {
		t.Fatal("main worktree config created")
	}
}

func TestDirenvErrors(t *testing.T) {
	t.Parallel()
	t.Run("outside git", func(t *testing.T) {
		root := t.TempDir()
		_, err := PrepareDirenv(context.Background(), ExecRunner{}, os.Environ(), root)
		if err == nil || !strings.Contains(err.Error(), "Git root") {
			t.Fatalf("err = %v", err)
		}
		if exists(filepath.Join(root, "mise.local.toml")) {
			t.Fatal("config created outside Git")
		}
	})
	t.Run("config is directory", func(t *testing.T) {
		root := t.TempDir()
		git(t, root, "init", "-q")
		mustMkdir(t, filepath.Join(root, "mise.local.toml"))
		_, err := PrepareDirenv(context.Background(), ExecRunner{}, os.Environ(), root)
		if err == nil || !strings.Contains(err.Error(), "not a file") {
			t.Fatalf("err = %v", err)
		}
	})
}

func TestGlobalIgnoreMiseLocal(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	git(t, root, "init", "-q")
	ignore := filepath.Join(repoRoot(t), "assets/dotfiles/gitignore")
	for _, path := range []string{
		"mise.local.toml", ".mise.local.toml", ".config/mise.local.toml",
		".config/mise/config.local.toml", ".mise/config.local.toml", "mise/config.local.toml",
	} {
		if got := git(t, root, "-c", "core.excludesFile="+ignore, "check-ignore", "--", path); got != path {
			t.Fatalf("ignored path = %q, want %q", got, path)
		}
	}
	writeFile(t, filepath.Join(root, "mise.toml"), "[env]\n")
	if got := git(t, root, "-c", "core.excludesFile="+ignore, "ls-files", "--others", "--exclude-standard"); got != "mise.toml" {
		t.Fatalf("visible files = %q", got)
	}
}
