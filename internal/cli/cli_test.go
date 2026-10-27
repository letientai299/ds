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
	return invokeWithIO(t, IO{}, args...)
}

func invokeWithIO(t *testing.T, sys IO, args ...string) (int, string, string) {
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
	sys.Stdin = strings.NewReader("")
	sys.Stdout, sys.Stderr = &stdout, &stderr
	sys.Environ = append([]string{"HOME=" + home, "PATH=/usr/bin:/bin"}, sys.Environ...)
	sys.Source = assets.Checkout{Root: root}
	sys.UID = 501
	code := Run(context.Background(), args, sys)
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
		{"direnv takes no arguments", []string{"direnv", "extra"}, 2, "unknown command"},
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

func TestStatusColor(t *testing.T) {
	for _, tt := range []struct {
		name  string
		io    IO
		json  bool
		color bool
	}{
		{name: "pipe"},
		{name: "terminal", io: IO{Color: true}, color: true},
		{name: "no color", io: IO{Color: true, Environ: []string{"NO_COLOR=1"}}},
		{name: "empty no color", io: IO{Color: true, Environ: []string{"NO_COLOR="}}, color: true},
		{name: "dumb terminal", io: IO{Color: true, Environ: []string{"TERM=dumb"}}},
		{name: "json", io: IO{Color: true}, json: true},
	} {
		t.Run(tt.name, func(t *testing.T) {
			args := []string{"status"}
			if tt.json {
				args = append(args, "--json")
			}
			code, stdout, stderr := invokeWithIO(t, tt.io, args...)
			if code != 0 || strings.Contains(stdout, "\x1b[") != tt.color {
				t.Fatalf("code %d, stdout %q, stderr %q", code, stdout, stderr)
			}
			if tt.json && !json.Valid([]byte(stdout)) {
				t.Fatalf("invalid JSON: %s", stdout)
			}
		})
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
