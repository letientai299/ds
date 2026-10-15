package ds

import (
	"bytes"
	"context"
	"encoding/json"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/letientai299/ds/internal/assets"
)

func TestStatusDiagnostics(t *testing.T) {
	for _, trial := range []bool{false, true} {
		t.Run(map[bool]string{false: "home", true: "trial"}[trial], func(t *testing.T) {
			f := newFixture(t)
			if trial {
				f.env.Target = TrialTarget{P: f.env.Target.Paths()}
			}
			missing := filepath.Join(f.home, "missing-nvim")
			f.env.Repos[assets.Nvim] = RepoSource{Dir: missing}
			f.env.Executable = "/cache/ds-checkout"
			before := snapshot(t, f.home)
			r := f.env.Status(context.Background(), f.state(), nil)
			if r.Runtime.Checkout.Root != repoRoot(t) || r.Runtime.Executable != f.env.Executable {
				t.Fatalf("runtime: %+v", r.Runtime)
			}
			if s := r.Runtime.Sources[assets.Nvim]; s.Path != missing || s.Error == "" {
				t.Fatalf("missing source: %+v", s)
			}
			if r.Paths["state"] != statePath(f.env.Target) || r.Paths["mise tools"] != fragmentPath(f.env.Target) {
				t.Fatalf("paths: %+v", r.Paths)
			}
			if r.Mise.State != compInstalled || r.Mise.Version != "2026.9.12" {
				t.Fatalf("mise: %+v", r.Mise)
			}
			if r.Healthy() || !reflect.DeepEqual(before, snapshot(t, f.home)) {
				t.Fatal("empty selection changed health or target files")
			}
			data, err := json.Marshal(r)
			if err != nil || !bytes.Contains(data, []byte(missing)) {
				t.Fatalf("JSON: %s, %v", data, err)
			}
		})
	}
}

func TestStatusToolDetails(t *testing.T) {
	f := newFixture(t)
	comp, _ := f.env.Catalog.Component("neovim")
	fact := toolFact{Version: "0.11.4", Requested: "latest", Installed: true, InstallPath: "/mise/nvim/0.11.4"}
	fact.Source.Path = "/config/mise/config.toml"
	for _, installed := range []bool{false, true} {
		fact.Installed = installed
		s := f.env.componentStatus(comp, miseFound{}, map[string]toolFact{comp.Tool.Name: fact})
		if s.Requested != fact.Requested || s.Source != fact.Source.Path || s.InstallPath != fact.InstallPath {
			t.Fatalf("tool details: %+v", s)
		}
		if s.Commands["nvim"] != filepath.Join(f.tools, "nvim") {
			t.Fatalf("command paths: %+v", s.Commands)
		}
		if (s.State == compInstalled) != installed {
			t.Fatalf("tool health: %+v", s)
		}
	}
}

func TestRenderStatusDetails(t *testing.T) {
	r := StatusReport{
		Summary:    SummaryComplete,
		Runtime:    VersionReport{Executable: "/bin/ds", Checkout: &CheckoutVersion{Root: "/src/ds", Commit: "abc", Dirty: true}},
		Mise:       ComponentStatus{State: compInstalled, Version: "2026.9.12", Detail: "/bin/mise"},
		Components: []ComponentStatus{{Name: "neovim", State: compInstalled, Version: "0.11.4", Requested: "latest", Source: "/mise/config.toml", InstallPath: "/mise/nvim", Commands: map[string]string{"nvim": "/bin/nvim"}}},
		Files:      []FileStatus{{Path: "/config/nvim", State: statePresent.String()}},
	}
	var out bytes.Buffer
	RenderStatus(&out, r, false, false)
	if !strings.Contains(out.String(), "installed   neovim (0.11.4; requested latest)\n") {
		t.Fatalf("missing compact versions: %s", out.String())
	}
	for _, hidden := range []string{"/config/nvim", "/bin/ds", "/bin/mise", "/src/ds", "/mise/config.toml", "/mise/nvim", "/bin/nvim", "\x1b["} {
		if strings.Contains(out.String(), hidden) {
			t.Fatalf("compact output includes %q: %s", hidden, out.String())
		}
	}
	out.Reset()
	RenderStatus(&out, r, true, false)
	for _, want := range []string{"executable: /bin/ds", "ds checkout /src/ds", "abc (dirty)", "mise: installed (2026.9.12; /bin/mise)", "installed   neovim", "request: latest (/mise/config.toml)", "install: /mise/nvim", "nvim: /bin/nvim", "/config/nvim"} {
		if !strings.Contains(out.String(), want) {
			t.Fatalf("missing %q: %s", want, out.String())
		}
	}
}

func TestRenderStatusHealth(t *testing.T) {
	for _, color := range []bool{false, true} {
		for _, tt := range []struct {
			state, code string
		}{
			{SummaryComplete, "32"},
			{SummaryIncomplete, "33"},
			{SummaryConflict, "31"},
		} {
			r := StatusReport{
				Summary: tt.state,
				Components: []ComponentStatus{
					{Name: "neovim", State: compInstalled, Version: "0.11.4", Requested: "0.11.4"},
					{Name: "tmux", State: compMissing, Requested: "latest", Detail: "tmux is not installed"},
					{Name: "kitty", State: compUnavailable, Detail: "unsupported platform"},
				},
				Files: []FileStatus{
					{Path: "/config/tmux", State: stateConflict.String(), Detail: "existing file"},
					{Path: "/config/zsh", State: stateStale.String()},
				},
			}
			var out bytes.Buffer
			RenderStatus(&out, r, false, color)
			for _, label := range []struct {
				text, code, tail string
			}{
				{tt.state, tt.code, "\n"},
				{compInstalled, "32", "   neovim (0.11.4)\n"},
				{compMissing, "33", "     tmux (requested latest; tmux is not installed)\n"},
				{compUnavailable, "31", " kitty (unsupported platform)\n"},
				{stateConflict.String(), "31", "    /config/tmux (existing file)\n"},
				{stateStale.String(), "33", "    /config/zsh\n"},
			} {
				want := label.text
				if color {
					want = "\x1b[" + label.code + "m" + want + "\x1b[0m"
				}
				want += label.tail
				if !strings.Contains(out.String(), want) {
					t.Fatalf("missing %q: %s", want, out.String())
				}
			}
			if !color && strings.Contains(out.String(), "\x1b[") {
				t.Fatalf("plain output contains ANSI escapes: %q", out.String())
			}
		}
	}
}

func TestStatusMainDiagnostics(t *testing.T) {
	f := newFixture(t)
	f.env.Source = embeddedBuild(t)
	r := f.env.Status(context.Background(), f.state(), nil)
	if r.Runtime.Build == nil || r.Build == nil || r.Build.Running != r.Runtime.Build.ID {
		t.Fatalf("main build diagnostics: %+v", r)
	}
	if r.Runtime.Checkout != nil || r.Build.Current != "" {
		t.Fatalf("unactivated main build: %+v", r)
	}
}

func TestStatusExternalTools(t *testing.T) {
	t.Parallel()
	for _, tt := range []struct {
		name, component string
		prepare         func(*testing.T, *fixture, string)
		installed       bool
	}{
		{name: "native claude", component: "claude", installed: true, prepare: func(t *testing.T, f *fixture, name string) {
			writeExec(t, filepath.Join(f.tools, name), fakeCommand)
		}},
		{name: "native bat", component: "bat", installed: true, prepare: func(t *testing.T, f *fixture, name string) {
			writeExec(t, filepath.Join(f.tools, name), fakeCommand)
		}},
		{name: "absent", component: "claude"},
		{name: "stale shim", component: "claude", prepare: func(t *testing.T, f *fixture, name string) {
			writeExec(t, filepath.Join(f.env.Target.Paths().MiseData, "shims", name), fakeCommand)
		}},
		{name: "unrequested mise install", component: "claude", prepare: func(t *testing.T, f *fixture, name string) {
			binary := filepath.Join(f.env.Target.Paths().MiseData, "installs", "claude-code", "1", name)
			writeExec(t, binary, fakeCommand)
			symlink(t, binary, filepath.Join(f.tools, name))
		}},
	} {
		t.Run(tt.name, func(t *testing.T) {
			f := newFixture(t)
			comp, _ := f.env.Catalog.Component(ComponentName(tt.component))
			if tt.prepare != nil {
				tt.prepare(t, f, comp.Commands[0])
			}
			before := snapshot(t, f.home)
			s := f.env.componentStatus(comp, miseFound{}, nil)
			if (s.State == compInstalled) != tt.installed {
				t.Fatalf("status: %+v", s)
			}
			if tt.installed {
				r := StatusReport{Components: []ComponentStatus{s}}
				if summarize(r) != SummaryComplete {
					t.Fatal("external tool is unhealthy")
				}
				for _, verbose := range []bool{false, true} {
					var out bytes.Buffer
					RenderStatus(&out, r, verbose, false)
					if !strings.Contains(out.String(), "installed   "+tt.component+" ("+externalToolDetail+")") {
						t.Fatalf("external detail missing: %s", out.String())
					}
				}
			}
			if !reflect.DeepEqual(before, snapshot(t, f.home)) {
				t.Fatal("status changed target files")
			}
		})
	}
}
