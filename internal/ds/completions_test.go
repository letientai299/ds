package ds

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestToolCompletions(t *testing.T) {
	t.Parallel()
	for _, tool := range []string{"bat", "eza", "fd", "rg", "xh", "ouch", "sd", "yazi", "ya", "delta", "tree-sitter", "codex"} {
		t.Run(tool, func(t *testing.T) {
			t.Parallel()
			dir := t.TempDir()
			prefix := filepath.Join(dir, "install with spaces")
			tools := filepath.Join(dir, "tools")
			content := "#compdef " + tool + "\n_arguments '--help[Show help]'\n"
			generator := map[string]string{
				"delta":       "--generate-completion zsh",
				"tree-sitter": "complete --shell zsh",
				"codex":       "completion zsh",
			}[tool]
			if generator != "" {
				binary := filepath.Join(prefix, "bin", "generator")
				writeExec(t, binary, `#!/bin/sh
[ "$*" = "$GENERATOR_ARGS" ] || exit 42
printf '%s' "$COMPLETION"
`)
				if err := os.Symlink("generator", filepath.Join(prefix, "bin", tool)); err != nil {
					t.Fatal(err)
				}
			} else if tool == "eza" {
				writeExec(t, filepath.Join(tools, "curl"), `#!/bin/sh
[ "$2" = "https://raw.githubusercontent.com/eza-community/eza/v0.23.5/completions/zsh/_eza" ] || exit 42
printf '%s' "$COMPLETION" > "$4"
`)
			} else {
				name := "_" + tool
				if tool == "bat" {
					name = "bat.zsh"
				}
				writeFile(t, filepath.Join(prefix, "archive", name), content)
			}
			for range 2 {
				cmd := exec.Command("sh", filepath.Join(repoRoot(t), "assets/tools/completion-postinstall"), tool)
				cmd.Env = append(os.Environ(), "MISE_TOOL_INSTALL_PATH="+prefix, "MISE_TOOL_VERSION=v0.23.5", "COMPLETION="+content, "GENERATOR_ARGS="+generator, "PATH="+tools+string(os.PathListSeparator)+os.Getenv("PATH"))
				if output, err := cmd.CombinedOutput(); err != nil {
					t.Fatalf("postinstall: %v\n%s", err, output)
				}
				got, err := os.ReadFile(filepath.Join(prefix, "share/zsh/site-functions/_"+tool))
				if err != nil || string(got) != content {
					t.Fatalf("completion: %q, %v", got, err)
				}
			}
		})
	}
}

func TestMissingCompletion(t *testing.T) {
	t.Parallel()
	prefix := filepath.Join(t.TempDir(), "install")
	cmd := exec.Command("sh", filepath.Join(repoRoot(t), "assets/tools/completion-postinstall"), "fd")
	cmd.Env = append(os.Environ(), "MISE_TOOL_INSTALL_PATH="+prefix)
	output, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(output), "Missing completion: fd") {
		t.Fatalf("missing completion: %v\n%s", err, output)
	}
	files, err := os.ReadDir(filepath.Join(prefix, "share/zsh/site-functions"))
	if err != nil || len(files) != 0 {
		t.Fatalf("partial completion remains: %v, %v", files, err)
	}
}

func TestCompletionDownloadFailure(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	prefix := filepath.Join(dir, "install")
	target := filepath.Join(prefix, "share/zsh/site-functions/_eza")
	writeFile(t, target, "existing completion\n")
	tools := filepath.Join(dir, "tools")
	writeExec(t, filepath.Join(tools, "curl"), "#!/bin/sh\nprintf partial > \"$4\"\nexit 22\n")
	cmd := exec.Command("sh", filepath.Join(repoRoot(t), "assets/tools/completion-postinstall"), "eza")
	cmd.Env = append(os.Environ(), "MISE_TOOL_INSTALL_PATH="+prefix, "MISE_TOOL_VERSION=0.23.5", "PATH="+tools+string(os.PathListSeparator)+os.Getenv("PATH"))
	if output, err := cmd.CombinedOutput(); err == nil {
		t.Fatalf("download succeeded: %s", output)
	}
	got, err := os.ReadFile(target)
	if err != nil || string(got) != "existing completion\n" {
		t.Fatalf("existing completion changed: %q, %v", got, err)
	}
	files, err := os.ReadDir(filepath.Dir(target))
	if err != nil || len(files) != 1 {
		t.Fatalf("temporary completion remains: %v, %v", files, err)
	}
}

func TestYaziCompletions(t *testing.T) {
	t.Parallel()
	prefix := filepath.Join(t.TempDir(), "install")
	for _, tool := range []string{"yazi", "ya"} {
		writeFile(t, filepath.Join(prefix, "completions/_"+tool), "#compdef "+tool+"\n")
	}
	cmd := exec.Command("sh", filepath.Join(repoRoot(t), "assets/tools/completion-postinstall"), "yazi", "ya")
	cmd.Env = append(os.Environ(), "MISE_TOOL_INSTALL_PATH="+prefix)
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("postinstall: %v\n%s", err, output)
	}
	for _, tool := range []string{"yazi", "ya"} {
		got := readFile(t, filepath.Join(prefix, "share/zsh/site-functions/_"+tool))
		if got != "#compdef "+tool+"\n" {
			t.Fatalf("%s completion: %q", tool, got)
		}
	}
}
