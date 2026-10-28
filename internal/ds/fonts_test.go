package ds

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/letientai299/ds/internal/assets"
)

// mockFontDownload keeps fixture installs offline while exercising verification
// and extraction through the same path as upstream releases.
func mockFontDownload(t *testing.T, f *fixture) {
	t.Helper()
	comp, _ := f.env.Catalog.Component("kitty")
	dir := t.TempDir()
	for _, name := range comp.Font.Files {
		writeFile(t, filepath.Join(dir, name), "fixture "+name)
	}
	archive := filepath.Join(t.TempDir(), "fonts.tar.xz")
	args := append([]string{"-cJf", archive, "-C", dir, "--"}, comp.Font.Files...)
	if out, err := exec.Command("tar", args...).CombinedOutput(); err != nil {
		t.Fatalf("create font archive: %v: %s", err, out)
	}
	data, err := os.ReadFile(archive)
	if err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write(data)
	}))
	t.Cleanup(srv.Close)
	comp.Font.URL = srv.URL + "/fonts.tar.xz"
	comp.Font.SHA256 = sum(data)
	f.env.HTTP = srv.Client()
}

func TestUIFonts(t *testing.T) {
	t.Parallel()
	for _, osName := range []string{"darwin", "linux"} {
		t.Run(osName, func(t *testing.T) {
			f := newFixture(t)
			paths := f.env.Target.Paths()
			paths.Data = filepath.Join(f.home, "custom-data")
			f.env.Target = HomeTarget{P: paths, OS: osName}
			f.env.Platform = Platform{OS: osName, Arch: "arm64", Glibc: "2.35"}
			fonts := filepath.Join(paths.Data, "fonts")
			if osName == "darwin" {
				fonts = filepath.Join(f.home, "Library", "Fonts")
			}
			ui := LayerRequest{Layers: []LayerName{"ui"}}
			machine := filepath.Join(f.env.Repos[assets.Kitty].Dir, "conf", "local", "machine.conf")
			writeFile(t, machine, "font_family Custom Font\n")
			f.add(ui, AddOptions{})
			config := filepath.Join(filepath.Dir(machine), "ds.conf")
			if got := readFile(t, config); !strings.Contains(got, "font_family Iosevka Nerd Font Mono\n") {
				t.Fatalf("font config missing: %q", got)
			}
			if got := readFile(t, machine); got != "font_family Custom Font\n" {
				t.Fatalf("machine preferences changed: %q", got)
			}
			for _, style := range []string{"Regular", "Bold", "Italic", "BoldItalic"} {
				name := "IosevkaNerdFontMono-" + style + ".ttf"
				target := filepath.Join(fonts, name)
				comp, _ := f.env.Catalog.Component("kitty")
				want := filepath.Join(paths.DSData(), "fonts", comp.Font.SHA256, name)
				if got, err := os.Readlink(target); err != nil || got != want {
					t.Fatalf("font link: %q, %v; want %q", got, err, want)
				}
				if info, err := os.Stat(target); err != nil || info.Size() == 0 {
					t.Fatalf("font not readable: %v", err)
				}
			}
			if again := f.env.BuildPlan(context.Background(), f.state(), ui, AddOptions{}); len(again.Actions) != 0 {
				t.Fatalf("second plan: %v", actionNames(again))
			}
			if r := f.env.Status(context.Background(), f.state(), nil); !r.Healthy() {
				t.Fatalf("installed fonts status: %+v", r.Files)
			}
			comp, _ := f.env.Catalog.Component("kitty")
			license := filepath.Join(paths.DSData(), "fonts", comp.Font.SHA256, "LICENSE.md")
			if err := os.Remove(license); err != nil {
				t.Fatal(err)
			}
			if r := f.env.Status(context.Background(), f.state(), nil); r.Healthy() {
				t.Fatal("incomplete font download is healthy")
			}
			if repair := f.env.BuildPlan(context.Background(), f.state(), ui, AddOptions{}); !hasAction(repair, "download and verify fonts") {
				t.Fatalf("missing file not repaired: %v", actionNames(repair))
			}
			f.add(ui, AddOptions{})
			if _, err := os.Stat(license); err != nil {
				t.Fatalf("license not restored: %v", err)
			}
		})
	}
}

func TestUIFontConflict(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	font := filepath.Join(f.home, "Library", "Fonts", "IosevkaNerdFontMono-Regular.ttf")
	writeFile(t, font, "user font")
	p := f.env.BuildPlan(context.Background(), f.state(), LayerRequest{Layers: []LayerName{"ui"}}, AddOptions{})
	if len(p.Blockers) != 1 || p.Blockers[0].Subject != font {
		t.Fatalf("font conflict: %v", p.Blockers)
	}
	if got := readFile(t, font); got != "user font" {
		t.Fatalf("user font changed: %q", got)
	}
}

func TestTrialSkipsFonts(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	f.env.Target = TrialTarget{P: f.env.Target.Paths()}
	p := f.env.BuildPlan(context.Background(), f.state(), LayerRequest{Layers: []LayerName{"ui"}}, AddOptions{})
	if len(p.Blockers) != 0 {
		t.Fatalf("trial blockers: %v", p.Blockers)
	}
	for _, entry := range p.Actions {
		if change, ok := entry.(FileChange); ok && filepath.Base(change.Entry.path()) == "ds.conf" {
			t.Fatal("trial creates local font config")
		}
		if _, ok := entry.(FetchFonts); ok {
			t.Fatal("trial downloads fonts")
		}
		if change, ok := entry.(FileChange); ok {
			if link, ok := change.Entry.(managedLink); ok && filepath.Ext(link.Target) == ".ttf" {
				t.Fatalf("trial installs font: %s", link.Target)
			}
		}
	}
}

func TestMainBuildFontConfig(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	f.env.Source = embeddedBuild(t)
	f.env.Executable = filepath.Join(t.TempDir(), "ds")
	writeExec(t, f.env.Executable, "#!/bin/sh\nexit 0\n")
	f.add(LayerRequest{Layers: []LayerName{"ui"}}, AddOptions{})
	config := filepath.Join(f.env.Repos[assets.Kitty].Dir, "conf", "local", "ds.conf")
	if got := readFile(t, config); !strings.Contains(got, "font_family Iosevka Nerd Font Mono\n") {
		t.Fatalf("main build font config missing: %q", got)
	}
}

func TestUIFontConfigConflict(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	config := filepath.Join(f.env.Repos[assets.Kitty].Dir, "conf", "local", "ds.conf")
	writeFile(t, config, "font_family Custom Font\n")
	p := f.env.BuildPlan(context.Background(), f.state(), LayerRequest{Layers: []LayerName{"ui"}}, AddOptions{})
	if len(p.Blockers) != 1 || p.Blockers[0].Subject != config {
		t.Fatalf("config conflict: %v", p.Blockers)
	}
	if got := readFile(t, config); got != "font_family Custom Font\n" {
		t.Fatalf("existing config changed: %q", got)
	}
}

func TestFontDownloadFailure(t *testing.T) {
	t.Parallel()
	for _, test := range []struct {
		name       string
		status     int
		body, want string
	}{
		{"checksum mismatch", http.StatusOK, "corrupt", "checksum mismatch"},
		{"HTTP failure", http.StatusNotFound, "missing", "404"},
		{"invalid archive", http.StatusOK, "invalid archive", "extract fonts"},
	} {
		t.Run(test.name, func(t *testing.T) {
			f := newFixture(t)
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(test.status)
				_, _ = w.Write([]byte(test.body))
			}))
			defer srv.Close()
			comp, _ := f.env.Catalog.Component("kitty")
			spec := *comp.Font
			spec.URL = srv.URL
			if test.name == "invalid archive" {
				spec.SHA256 = sum([]byte(test.body))
			}
			dir := filepath.Join(t.TempDir(), "fonts")
			err := f.env.fetchFonts(context.Background(), FetchFonts{Spec: spec, Dir: dir, Tar: "tar"})
			if err == nil || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("error = %v; want %q", err, test.want)
			}
			if _, err := os.Stat(dir); !os.IsNotExist(err) {
				t.Fatalf("failed download installed fonts: %v", err)
			}
		})
	}
}

func TestFontDryRunDoesNotDownload(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	var requests atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { requests.Add(1) }))
	defer srv.Close()
	comp, _ := f.env.Catalog.Component("kitty")
	comp.Font.URL = srv.URL
	p := f.env.BuildPlan(context.Background(), f.state(), LayerRequest{Layers: []LayerName{"ui"}}, AddOptions{})
	if requests.Load() != 0 || !hasAction(p, "download and verify fonts") {
		t.Fatalf("dry run: requests=%d, actions=%v", requests.Load(), actionNames(p))
	}
}

func TestFontSpecValidation(t *testing.T) {
	t.Parallel()
	for _, test := range []struct {
		name, sha string
		files     []string
	}{
		{"bad checksum", "invalid", []string{"font.ttf"}},
		{"missing files", strings.Repeat("0", 64), nil},
		{"path traversal", strings.Repeat("0", 64), []string{"../font.ttf"}},
		{"absolute path", strings.Repeat("0", 64), []string{"/font.ttf"}},
		{"parent", strings.Repeat("0", 64), []string{".."}},
		{"option", strings.Repeat("0", 64), []string{"-font.ttf"}},
		{"duplicate", strings.Repeat("0", 64), []string{"font.ttf", "font.ttf"}},
	} {
		t.Run(test.name, func(t *testing.T) {
			if err := (FontSpec{URL: "https://example.com/fonts.tar.xz", SHA256: test.sha, Files: test.files}).validate(); err == nil {
				t.Fatal("invalid font spec accepted")
			}
		})
	}
}
