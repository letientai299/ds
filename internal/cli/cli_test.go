package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/letientai299/ds/internal/assets"
)

func invoke(t *testing.T, args ...string) (int, string, string) {
	t.Helper()
	_, file, _, _ := runtime.Caller(0)
	root := filepath.Clean(filepath.Join(filepath.Dir(file), "..", ".."))
	dir := t.TempDir()
	repos := map[assets.Repo]string{}
	for _, repo := range assets.ConfigRepos {
		repos[repo] = filepath.Join(dir, repo.CheckoutName())
		if err := os.MkdirAll(repos[repo], 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(repos[assets.Tmux], "tm"), []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	var cfg strings.Builder
	cfg.WriteString("[sources]\n")
	for repo, dir := range repos {
		fmt.Fprintf(&cfg, "%s = %q\n", repo, dir)
	}
	home := filepath.Join(dir, "home")
	if err := os.MkdirAll(filepath.Join(home, ".config", "ds"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, ".config", "ds", "config.toml"), []byte(cfg.String()), 0o644); err != nil {
		t.Fatal(err)
	}
	var stdout, stderr bytes.Buffer
	code := Run(context.Background(), args, IO{
		Stdin:   strings.NewReader(""),
		Stdout:  &stdout,
		Stderr:  &stderr,
		Environ: []string{"HOME=" + home, "PATH=/usr/bin:/bin"},
		Source:  assets.Checkout{Root: root},
		UID:     501,
	})
	return code, stdout.String(), stderr.String()
}

func TestExitCodes(t *testing.T) {
	tests := []struct {
		name   string
		args   []string
		code   int
		stderr string
	}{
		{"mixed selectors", []string{"add", "-l", "ui", "neovim"}, 2, "not both"},
		{"bare add", []string{"add"}, 2, "add needs components or --layer"},
		{"unknown layer", []string{"add", "-l", "remote"}, 2, `unknown layer "remote"`},
		{"positional layer", []string{"add", "core"}, 2, "use --layer core"},
		{"unknown flag", []string{"status", "--bogus"}, 2, "unknown flag"},
		{"unknown command", []string{"frobnicate"}, 2, "unknown command"},
		{"incompatible skip", []string{"upgrade", "system", "--skip", "system"}, 2, "cannot both upgrade and skip"},
		{"deploy without host", []string{"deploy"}, 2, "needs a HOST"},
		{"layer flag takes one name", []string{"status", "-l", "core,extra"}, 2, `unknown layer "core,extra"`},
		{"unhealthy check", []string{"status", "--check"}, 1, ""},
		{"unhealthy report", []string{"status"}, 0, ""},
		{"inspect unsaved target", []string{"status", "tmux"}, 0, ""},
		{"preview", []string{"add", "-l", "core", "--dry-run"}, 0, ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			code, _, stderr := invoke(t, tt.args...)
			if code != tt.code || !strings.Contains(stderr, tt.stderr) {
				t.Fatalf("code %d stderr %q", code, stderr)
			}
		})
	}
}

func TestJSONGoesToStdout(t *testing.T) {
	code, stdout, stderr := invoke(t, "status", "--json", "-l", "core")
	if code != 0 {
		t.Fatalf("code %d: %s", code, stderr)
	}
	var report map[string]any
	if err := json.Unmarshal([]byte(stdout), &report); err != nil {
		t.Fatalf("stdout is not JSON: %v\n%s", err, stdout)
	}
	if report["mode"] != "checkout" || report["summary"] != "incomplete" {
		t.Fatalf("report = %v", report)
	}
}

func TestVersionAndCompletion(t *testing.T) {
	code, stdout, _ := invoke(t, "version", "--json")
	if code != 0 || !strings.Contains(stdout, `"mode": "checkout"`) {
		t.Fatalf("version: %d %s", code, stdout)
	}
	code, stdout, _ = invoke(t, "completion", "zsh")
	if code != 0 || !strings.HasPrefix(stdout, "#compdef ds") {
		t.Fatalf("completion: %d %.40q", code, stdout)
	}
}

func TestEnvKeepsHomeFlag(t *testing.T) {
	_, file, _, _ := runtime.Caller(0)
	root := filepath.Clean(filepath.Join(filepath.Dir(file), "..", ".."))
	home := t.TempDir()
	a := &app{io: IO{
		Stdout: &bytes.Buffer{}, Stderr: &bytes.Buffer{},
		Environ: []string{"HOME=/nonexistent"},
		Source:  assets.Checkout{Root: root},
	}}
	cmd := a.rootCmd()
	cmd.SetArgs([]string{"--home", home, "version"})
	cmd.SetOut(&bytes.Buffer{})
	if err := cmd.Execute(); err != nil {
		t.Fatal(err)
	}
	if a.home != home {
		t.Fatalf("--home lost after building the environment: %q", a.home)
	}
}
