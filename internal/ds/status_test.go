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
		Components: []ComponentStatus{{Name: "neovim", State: compInstalled, Version: "0.11.4", Requested: "latest", Source: "/mise/config.toml", InstallPath: "/mise/nvim", Commands: map[string]string{"nvim": "/bin/nvim"}}},
		Files:      []FileStatus{{Path: "/config/nvim", State: statePresent.String()}},
	}
	var out bytes.Buffer
	RenderStatus(&out, r, false)
	for _, want := range []string{"executable: /bin/ds", "ds checkout /src/ds", "abc (dirty)", "installed   neovim", "request: latest (/mise/config.toml)", "install: /mise/nvim", "nvim: /bin/nvim"} {
		if !strings.Contains(out.String(), want) {
			t.Fatalf("missing %q: %s", want, out.String())
		}
	}
	if strings.Contains(out.String(), "/config/nvim") {
		t.Fatal("healthy managed file shown without verbose")
	}
	out.Reset()
	RenderStatus(&out, r, true)
	if !strings.Contains(out.String(), "/config/nvim") {
		t.Fatal("verbose omitted healthy managed file")
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
