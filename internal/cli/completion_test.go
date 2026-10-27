package cli

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/letientai299/ds/internal/assets"
)

func TestArgumentCompletion(t *testing.T) {
	tests := []struct {
		name string
		args []string
		want []string
	}{
		{"component prefix", []string{"add", "t"}, []string{"tree-sitter", "tmux"}},
		{"selected component", []string{"add", "tmux", "t"}, []string{"tree-sitter"}},
		{"short layer flag", []string{"add", "-l", ""}, []string{"ai", "core", "extra", "ui"}},
		{"long layer flag", []string{"add", "--layer", "e"}, []string{"extra"}},
		{"equals layer flag", []string{"add", "--layer=u"}, []string{"ui"}},
		{"selected layer", []string{"add", "-l", "core", "-l", ""}, []string{"ai", "extra", "ui"}},
		{"layer excludes components", []string{"add", "-l", "core", ""}, nil},
		{"component excludes layers", []string{"add", "tmux", "-l", ""}, nil},
		{"status components", []string{"status", "n"}, []string{"neovim"}},
		{"status layers", []string{"status", "--layer", "u"}, []string{"ui"}},
		{"deploy needs host", []string{"deploy", ""}, nil},
		{"deploy components", []string{"deploy", "example", "n"}, []string{"neovim"}},
		{"deploy host matches component", []string{"deploy", "neovim", "n"}, []string{"neovim"}},
		{"deploy layers", []string{"deploy", "example", "-l", ""}, []string{"ai", "core", "extra", "ui"}},
		{"deploy layers before host", []string{"deploy", "-l", ""}, []string{"ai", "core", "extra", "ui"}},
		{"deploy selected component", []string{"deploy", "example", "tmux", "t"}, []string{"tree-sitter"}},
		{"deploy component excludes layers", []string{"deploy", "example", "tmux", "-l", ""}, nil},
		{"deploy layer excludes components", []string{"deploy", "example", "-l", "core", ""}, nil},
		{"upgrade categories", []string{"upgrade", ""}, []string{"ds", "tools", "plugins", "system", "all"}},
		{"upgrade repeated arguments", []string{"upgrade", "ds", ""}, []string{"tools", "plugins", "system", "all"}},
		{"upgrade prefix", []string{"upgrade", "tools", "s"}, []string{"system"}},
		{"upgrade all selected", []string{"upgrade", "all", ""}, nil},
		{"upgrade skipped category", []string{"upgrade", "--skip", "system", ""}, []string{"ds", "tools", "plugins", "all"}},
		{"skip categories", []string{"upgrade", "--skip", ""}, []string{"ds", "tools", "plugins", "system"}},
		{"skip selected category", []string{"upgrade", "tools", "--skip", ""}, []string{"ds", "plugins", "system"}},
		{"skip repeated flag", []string{"upgrade", "--skip", "system", "--skip", ""}, []string{"ds", "tools", "plugins"}},
		{"skip with all", []string{"upgrade", "all", "--skip", "s"}, []string{"system"}},
		{"skip last category", []string{"upgrade", "--skip", "ds", "--skip", "tools", "--skip", "plugins", "--skip", ""}, nil},
		{"skip last category with all", []string{"upgrade", "all", "--skip", "ds", "--skip", "tools", "--skip", "plugins", "--skip", ""}, nil},
		{"upgrade every category skipped", []string{"upgrade", "--skip", "ds", "--skip", "tools", "--skip", "plugins", "--skip", "system", ""}, nil},
		{"completion shells", []string{"completion", ""}, []string{"zsh", "bash"}},
		{"completion takes one shell", []string{"completion", "zsh", ""}, nil},
		{"shell has no arguments", []string{"shell", ""}, nil},
		{"direnv has no arguments", []string{"direnv", ""}, nil},
		{"version has no arguments", []string{"version", ""}, nil},
		{"unknown component prefix", []string{"add", "zz"}, nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			code, stdout, stderr := invoke(t, append([]string{"__complete"}, tt.args...)...)
			if code != 0 || !strings.HasSuffix(stdout, ":4\n") {
				t.Fatalf("completion: code %d, stdout %q, stderr %q", code, stdout, stderr)
			}
			var got []string
			for line := range strings.SplitSeq(strings.TrimSuffix(stdout, ":4\n"), "\n") {
				if line != "" {
					name, _, _ := strings.Cut(line, "\t")
					got = append(got, name)
				}
			}
			if !slices.Equal(got, tt.want) {
				t.Fatalf("completions = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestCatalogDiscovery(t *testing.T) {
	root := t.TempDir()
	if err := os.Mkdir(filepath.Join(root, "assets"), 0o755); err != nil {
		t.Fatal(err)
	}
	data := "[layers]\ncustom = ['mise', 'widget']\n[components.mise]\n" +
		"commands = ['mise']\n[components.widget]\ncommands = ['widget']\n"
	if err := os.WriteFile(filepath.Join(root, "assets", "catalog.toml"), []byte(data), 0o644); err != nil {
		t.Fatal(err)
	}
	home := t.TempDir()
	if err := os.MkdirAll(filepath.Join(home, ".config", "ds"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, ".config", "ds", "config.toml"), []byte("invalid = ["), 0o644); err != nil {
		t.Fatal(err)
	}
	tests := []struct {
		args []string
		want []string
	}{
		{[]string{"__complete", "add", ""}, []string{"mise\nwidget\n:4\n"}},
		{[]string{"__complete", "add", "-l", ""}, []string{"custom\tmise, widget\n:4\n"}},
		{[]string{"help", "add"}, []string{"Components:\n  mise, widget", "Layers (-l, --layer):\n  custom  mise, widget"}},
		{[]string{"status", "--help"}, []string{"mise, widget", "custom  mise, widget"}},
		{[]string{"help", "deploy"}, []string{"mise, widget", "custom  mise, widget"}},
	}
	for _, tt := range tests {
		t.Run(strings.Join(tt.args, " "), func(t *testing.T) {
			var stdout, stderr bytes.Buffer
			code := Run(context.Background(), tt.args, IO{
				Stdout: &stdout, Stderr: &stderr,
				Environ: []string{"HOME=" + home},
				Source:  assets.Checkout{Root: root},
			})
			if code != 0 || strings.Contains(stderr.String(), "invalid") {
				t.Fatalf("discovery: code %d, stderr %q", code, stderr.String())
			}
			for _, want := range tt.want {
				if !strings.Contains(stdout.String(), want) {
					t.Fatalf("output %q lacks %q", stdout.String(), want)
				}
			}
		})
	}
}

func TestSelectorHelp(t *testing.T) {
	for _, command := range []string{"add", "status", "deploy"} {
		t.Run(command, func(t *testing.T) {
			code, help, stderr := invoke(t, "help", command)
			if code != 0 || stderr != "" {
				t.Fatalf("help: code %d, stderr %q", code, stderr)
			}
			_, flagHelp, _ := invoke(t, command, "--help")
			if help != flagHelp {
				t.Fatalf("help COMMAND and COMMAND --help differ")
			}
			for _, want := range []string{"Components:", "Layers (-l, --layer):", "Select components or layers, never both.", "core", "extra", "ui", "neovim"} {
				if !strings.Contains(help, want) {
					t.Fatalf("help lacks %q: %s", want, help)
				}
			}
		})
	}
	code, help, stderr := invoke(t, "help", "upgrade")
	if code != 0 || stderr != "" || !strings.Contains(help, "Categories:") || !strings.Contains(help, "Upgrade selected mise tools") {
		t.Fatalf("upgrade help: code %d, stdout %q, stderr %q", code, help, stderr)
	}
}

func TestHomeCompletion(t *testing.T) {
	code, stdout, stderr := invoke(t, "__complete", "add", "--home", "")
	if code != 0 || stdout != ":16\n" {
		t.Fatalf("home completion: code %d, stdout %q, stderr %q", code, stdout, stderr)
	}
	code, stdout, stderr = invoke(t, "__complete", "deploy", "example", "--home", "")
	if code != 0 || stdout != ":4\n" {
		t.Fatalf("remote home completion: code %d, stdout %q, stderr %q", code, stdout, stderr)
	}
}
