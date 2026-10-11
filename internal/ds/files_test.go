package ds

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestResolvePaths(t *testing.T) {
	t.Parallel()
	env := map[string]string{
		"HOME":            "/home/me",
		"XDG_CONFIG_HOME": "/elsewhere/config",
		"MISE_DATA_DIR":   "/elsewhere/mise",
	}
	getenv := func(k string) string { return env[k] }
	tests := []struct {
		name, home, config, miseData string
	}{
		{"default honors XDG", "", "/elsewhere/config", "/elsewhere/mise"},
		{"explicit home ignores inherited paths", "/scratch/job/home", "/scratch/job/home/.config", "/scratch/job/home/.local/share/mise"},
		{"relative home resolves against login home", "jobs/one", "/home/me/jobs/one/.config", "/home/me/jobs/one/.local/share/mise"},
		{"tilde", "~/alt home", "/home/me/alt home/.config", "/home/me/alt home/.local/share/mise"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p, err := ResolvePaths(getenv, tt.home)
			if err != nil {
				t.Fatal(err)
			}
			if p.Config != tt.config || p.MiseData != tt.miseData {
				t.Fatalf("config %s mise %s", p.Config, p.MiseData)
			}
		})
	}
}

func TestBlockStates(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	body := `source "/x/shell.zsh"`
	tests := []struct {
		name    string
		content *string
		symlink bool
		want    fileState
		locked  bool
	}{
		{name: "missing file", want: stateMissing},
		{name: "no block", content: ptr("export A=1\n"), want: stateMissing},
		{name: "same block", content: ptr("a\n" + renderBlock(body) + "b\n"), want: statePresent},
		{name: "old block", content: ptr(renderBlock(`source "/old"`)), want: stateStale},
		{name: "unterminated", content: ptr(blockStart + "\nx\n"), want: stateConflict},
		{name: "repeated", content: ptr(renderBlock(body) + renderBlock(body)), want: stateConflict},
		{name: "orphan end", content: ptr("x\n" + blockEnd + "\n"), want: stateConflict},
		{name: "symlinked rc", symlink: true, want: stateConflict, locked: true},
	}
	for i, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			target := filepath.Join(dir, "rc"+string(rune('a'+i)))
			if tt.content != nil {
				writeFile(t, target, *tt.content)
			}
			if tt.symlink {
				writeFile(t, target+".real", "x\n")
				if err := os.Symlink(target+".real", target); err != nil {
					t.Fatal(err)
				}
			}
			got := managedBlock{Target: target, Body: body}.inspect(nil, nil)
			if got.State != tt.want || got.Locked != tt.locked {
				t.Fatalf("got %+v, want %s locked=%t", got, tt.want, tt.locked)
			}
		})
	}
}

func ptr(s string) *string { return &s }

func TestBlockWritePreservesUserContent(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name, before, want string
	}{
		{"append without newline", "user", "user\n" + renderBlock("B")},
		{"replace in place", "top\n" + renderBlock("old") + "bottom\n", "top\n" + renderBlock("B") + "bottom\n"},
		{"strip malformed", "a\n" + blockStart + "\nkept\n" + renderBlock("x") + blockEnd + "\n", "a\nkept\n" + renderBlock("B")},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			target := filepath.Join(t.TempDir(), "rc")
			writeFile(t, target, tt.before)
			if err := os.Chmod(target, 0o600); err != nil {
				t.Fatal(err)
			}
			if _, err := (managedBlock{Target: target, Body: "B"}).write(true); err != nil {
				t.Fatal(err)
			}
			if got := readFile(t, target); got != tt.want {
				t.Fatalf("got %q, want %q", got, tt.want)
			}
			if info, _ := os.Stat(target); info.Mode().Perm() != 0o600 {
				t.Fatalf("mode changed to %v", info.Mode())
			}
		})
	}
}

func TestLinkStates(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	source := filepath.Join(dir, "assets", "shell.zsh")
	writeFile(t, source, "x")
	legacy := filepath.Join(dir, "old-checkout")
	tests := []struct {
		name  string
		setup func(target string)
		own   map[string]Ownership
		want  fileState
	}{
		{name: "missing", setup: func(string) {}, want: stateMissing},
		{name: "present", setup: func(p string) { symlink(t, source, p) }, want: statePresent},
		{name: "recorded owner", setup: func(p string) { symlink(t, "/gone", p) },
			own: map[string]Ownership{}, want: stateStale},
		{name: "legacy root", setup: func(p string) { symlink(t, filepath.Join(legacy, "src", "shell.zsh"), p) }, want: stateStale},
		{name: "foreign link", setup: func(p string) { symlink(t, "/etc/hosts", p) }, want: stateConflict},
		{name: "regular file", setup: func(p string) { writeFile(t, p, "mine") }, want: stateConflict},
	}
	for i, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			target := filepath.Join(dir, "home", string(rune('a'+i)))
			mustMkdir(t, filepath.Dir(target))
			tt.setup(target)
			if tt.own != nil {
				tt.own[target] = Ownership{Kind: ownLink, Source: "/gone"}
			}
			got := managedLink{Target: target, Source: source}.inspect(tt.own, []string{legacy})
			if got.State != tt.want {
				t.Fatalf("got %+v, want %s", got, tt.want)
			}
		})
	}
}

func TestGeneratedFileOwnership(t *testing.T) {
	t.Parallel()
	target := filepath.Join(t.TempDir(), "conf.d", "10-ds.toml")
	f := managedFile{Target: target, Content: []byte("new\n"), Mode: 0o644}
	if got := f.inspect(nil, nil).State; got != stateMissing {
		t.Fatalf("got %s", got)
	}
	own, err := (managedFile{Target: target, Content: []byte("old\n"), Mode: 0o644}).write(false)
	if err != nil {
		t.Fatal(err)
	}
	owned := map[string]Ownership{target: own}
	if got := f.inspect(owned, nil).State; got != stateStale {
		t.Fatalf("unchanged ds content must be replaceable, got %s", got)
	}
	writeFile(t, target, "user edit\n")
	if got := f.inspect(owned, nil); got.State != stateConflict || !strings.Contains(got.Reason, "differs") {
		t.Fatalf("user edit must conflict, got %+v", got)
	}
}

func symlink(t *testing.T, dest, p string) {
	t.Helper()
	if err := os.Symlink(dest, p); err != nil {
		t.Fatal(err)
	}
}
