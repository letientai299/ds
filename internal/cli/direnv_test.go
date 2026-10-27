package cli

import (
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/letientai299/ds/internal/ds"
)

type direnvRunner struct {
	root   string
	editor ds.Cmd
	err    error
}

func (r *direnvRunner) Run(ctx context.Context, cmd ds.Cmd) error {
	if cmd.Args[0] == "git" {
		_, err := io.WriteString(cmd.Stdout, r.root+"\n")
		return err
	}
	r.editor = cmd
	return r.err
}

func TestDirenvEditor(t *testing.T) {
	for _, tt := range []struct {
		name    string
		environ []string
		want    string
	}{
		{name: "fallback", want: "vi"},
		{name: "editor arguments", environ: []string{"EDITOR=nvim -f"}, want: "nvim -f"},
		{name: "visual wins", environ: []string{"EDITOR=vi", "VISUAL=code --wait"}, want: "code --wait"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			runner := &direnvRunner{root: filepath.Join(t.TempDir(), "project 'with spaces")}
			if err := os.Mkdir(runner.root, 0o755); err != nil {
				t.Fatal(err)
			}
			code, _, stderr := invokeWithIO(t, IO{Runner: runner, Environ: tt.environ}, "direnv")
			if code != 0 {
				t.Fatalf("code = %d, stderr = %q", code, stderr)
			}
			want := []string{"sh", "-c", `exec ` + tt.want + ` "$@"`, "ds-direnv", filepath.Join(runner.root, "mise.local.toml")}
			if !slices.Equal(runner.editor.Args, want) {
				t.Fatalf("editor = %q, want %q", runner.editor.Args, want)
			}
			if runner.editor.Stdin == nil || runner.editor.Stdout == nil || runner.editor.Stderr == nil {
				t.Fatal("editor streams missing")
			}
		})
	}
}

func TestDirenvEditorFailure(t *testing.T) {
	runner := &direnvRunner{root: t.TempDir(), err: errors.New("editor failed")}
	code, _, stderr := invokeWithIO(t, IO{Runner: runner}, "direnv")
	if code != 1 || !strings.Contains(stderr, "editor failed") {
		t.Fatalf("code = %d, stderr = %q", code, stderr)
	}
}

func TestDirenvRelativeEditor(t *testing.T) {
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Chdir(root)
	if err := os.Mkdir(filepath.Join(root, ".config"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, ".config/mise.toml"), []byte("[env]\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "editor"), []byte("#!/bin/sh\nprintf '%s\\n' \"$PWD\" \"$@\"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	runner := &direnvRunner{root: root}
	code, _, stderr := invokeWithIO(t, IO{Runner: runner, Environ: []string{"EDITOR=./editor"}}, "direnv")
	if code != 0 {
		t.Fatalf("code = %d, stderr = %q", code, stderr)
	}
	var out strings.Builder
	runner.editor.Stdout = &out
	if err := (ds.ExecRunner{}).Run(context.Background(), runner.editor); err != nil {
		t.Fatal(err)
	}
	if want := root + "\n" + filepath.Join(root, ".config/mise.local.toml") + "\n"; out.String() != want {
		t.Fatalf("editor output = %q, want %q", out.String(), want)
	}
}

func TestDirenvEditorQuoting(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "project '$(touch injected)", "mise.local.toml")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	editor := filepath.Join(root, "custom editor")
	if err := os.WriteFile(editor, []byte("#!/bin/sh\nprintf '%s\\n' \"$@\"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	runner := &direnvRunner{root: filepath.Dir(path)}
	code, _, stderr := invokeWithIO(t, IO{Runner: runner, Environ: []string{"EDITOR='" + editor + "' --wait"}}, "direnv")
	if code != 0 {
		t.Fatalf("code = %d, stderr = %q", code, stderr)
	}
	var out strings.Builder
	runner.editor.Stdout = &out
	if err := (ds.ExecRunner{}).Run(context.Background(), runner.editor); err != nil {
		t.Fatal(err)
	}
	if want := "--wait\n" + path + "\n"; out.String() != want {
		t.Fatalf("editor arguments = %q, want %q", out.String(), want)
	}
	if _, err := os.Stat(filepath.Join(filepath.Dir(path), "injected")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("filename executed: %v", err)
	}
}
