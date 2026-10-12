package ds

import (
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func TestShippedCatalogIsValid(t *testing.T) {
	t.Parallel()
	data, err := os.ReadFile(filepath.Join(repoRoot(t), "assets", "catalog.toml"))
	if err != nil {
		t.Fatal(err)
	}
	cat, err := ParseCatalog(data)
	if err != nil {
		t.Fatal(err)
	}
	if got := joinNames(cat.Layers(), ","); got != "ai,core,extra,ui" {
		t.Fatalf("layers = %s", got)
	}
	core := cat.LayerMembers("core")
	for _, want := range []ComponentName{"tmux", "yazi", "neovim", "mise"} {
		if !slices.Contains(core, want) {
			t.Errorf("core lacks %s", want)
		}
	}
	if _, ok := cat.Component("docker"); ok {
		t.Error("docker component must not exist")
	}
}

const base = `
[layers]
one = ["a"]
[components.mise]
commands = ["mise"]
[components.a]
commands = ["a"]
`

func TestCatalogValidation(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name, extra, want string
	}{
		{"layer redeclared", `[layers.extra]`, "decode catalog"},
		{"cycle", `[components.b]
commands = ["b"]
requires = ["c"]
[components.c]
commands = ["c"]
requires = ["b"]`, "dependency cycle"},
		{"missing dependency", `[components.b]
commands = ["b"]
requires = ["nope"]`, "requires unknown component nope"},
		{"tool without mise", `[components.b]
commands = ["b"]
tool = { name = "b", version = "latest" }`, "does not require mise"},
		{"duplicate tool", `[components.b]
commands = ["b"]
requires = ["mise"]
tool = { name = "x", version = "latest" }
[components.c]
commands = ["c"]
requires = ["mise"]
tool = { name = "x", version = "latest" }`, "both own tool x"},
		{"duplicate target", `[components.b]
commands = ["b"]
links = [{ target = "{ds}/x", source = "ds:x" }]
[components.c]
commands = ["c"]
blocks = [{ target = "{ds}/x", text = "y" }]`, "both own {ds}/x"},
		{"bad placeholder", `[components.b]
commands = ["b"]
links = [{ target = "{home}/x", source = "ds:x" }]`, "invalid target"},
		{"bad source", `[components.b]
commands = ["b"]
links = [{ target = "{ds}/x", source = "docker:x" }]`, "invalid asset reference"},
		{"repository without URL", `[components.b]
commands = ["b"]
links = [{ target = "{ds}/x", source = "nvim:x" }]`, "repository nvim has no URL"},
		{"unknown repository", `[repos]
docker = "https://example.invalid/docker"`, `invalid repository "docker"`},
		{"unknown manager", `[components.b]
commands = ["b"]
packages = { dnf = ["b"] }`, "unsupported package manager dnf"},
		{"unknown field", `[components.b]
commands = ["b"]
optional = true`, "decode catalog"},
		{"tool without version", `[components.b]
commands = ["b"]
requires = ["mise"]
tool = { name = "b" }`, "requires a version"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := ParseCatalog([]byte(base + tt.extra))
			if err == nil || !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("err = %v, want %q", err, tt.want)
			}
		})
	}
}

func TestCatalogUnknownLayerMember(t *testing.T) {
	t.Parallel()
	input := strings.Replace(base, `one = ["a"]`, `one = ["a", "missing"]`, 1)
	if _, err := ParseCatalog([]byte(input)); err == nil || !strings.Contains(err.Error(), "unknown component missing") {
		t.Fatalf("err = %v", err)
	}
}

func testCatalog(t *testing.T) *Catalog {
	t.Helper()
	cat, err := ParseCatalog([]byte(`
[layers]
core = ["mise", "git", "neovim", "tmux"]
extra = ["bat"]
[components.mise]
commands = ["mise"]
[components.git]
commands = ["git"]
[components.neovim]
commands = ["nvim"]
requires = ["mise", "git"]
tool = { name = "neovim", version = "latest" }
[components.tmux]
commands = ["tmux"]
[components.bat]
commands = ["bat"]
requires = ["mise"]
tool = { name = "bat", version = "latest" }
`))
	if err != nil {
		t.Fatal(err)
	}
	return cat
}

func TestParseRequest(t *testing.T) {
	t.Parallel()
	cat := testCatalog(t)
	tests := []struct {
		name          string
		layers, comps []string
		want          Request
		err           string
	}{
		{name: "none"},
		{name: "layers dedupe", layers: []string{"extra", "core", "extra"}, want: LayerRequest{Layers: []LayerName{"core", "extra"}}},
		{name: "components", comps: []string{"tmux", "bat"}, want: ComponentRequest{Components: []ComponentName{"bat", "tmux"}}},
		{name: "mixed", layers: []string{"core"}, comps: []string{"neovim"}, err: "not both"},
		{name: "unknown layer", layers: []string{"remote"}, err: `unknown layer "remote"`},
		{name: "positional layer", comps: []string{"core"}, err: "use --layer core"},
		{name: "unknown component", comps: []string{"docker"}, err: `unknown component "docker"`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ParseRequest(cat, tt.layers, tt.comps)
			if tt.err != "" {
				var usage *UsageError
				if !errors.As(err, &usage) || !strings.Contains(err.Error(), tt.err) {
					t.Fatalf("err = %v, want usage error %q", err, tt.err)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if !requestEqual(got, tt.want) {
				t.Fatalf("got %#v, want %#v", got, tt.want)
			}
		})
	}
}

func requestEqual(a, b Request) bool {
	switch a := a.(type) {
	case nil:
		return b == nil
	case LayerRequest:
		b, ok := b.(LayerRequest)
		return ok && slices.Equal(a.Layers, b.Layers)
	case ComponentRequest:
		b, ok := b.(ComponentRequest)
		return ok && slices.Equal(a.Components, b.Components)
	}
	return false
}

func TestSelectionExpand(t *testing.T) {
	t.Parallel()
	cat := testCatalog(t)
	tests := []struct {
		name string
		sel  Selection
		want string
	}{
		{"standalone pulls dependencies", Selection{Components: []ComponentName{"neovim"}}, "mise git neovim"},
		{"layer", Selection{Layers: []LayerName{"extra"}}, "mise bat"},
		{"union dedupes", Selection{Layers: []LayerName{"core"}, Components: []ComponentName{"neovim", "bat"}}, "mise git neovim tmux bat"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := joinNames(cat.Expand(tt.sel), " "); got != tt.want {
				t.Fatalf("got %s, want %s", got, tt.want)
			}
		})
	}
}

func TestSelectionUnionIsAdditive(t *testing.T) {
	t.Parallel()
	s := Selection{Layers: []LayerName{"core"}}
	s = s.Union(ComponentRequest{Components: []ComponentName{"bat"}})
	s = s.Union(LayerRequest{Layers: []LayerName{"core", "extra"}})
	if got := s.String(); got != "-l core -l extra bat" {
		t.Fatalf("got %s", got)
	}
}

func TestLayerGrowthReachesSavedSelection(t *testing.T) {
	t.Parallel()
	saved := Selection{Layers: []LayerName{"extra"}}
	before := testCatalog(t)
	after, err := ParseCatalog([]byte(`
[layers]
extra = ["bat", "eza"]
[components.mise]
commands = ["mise"]
[components.bat]
commands = ["bat"]
requires = ["mise"]
tool = { name = "bat", version = "latest" }
[components.eza]
commands = ["eza"]
requires = ["mise"]
tool = { name = "eza", version = "latest" }
`))
	if err != nil {
		t.Fatal(err)
	}
	if slices.Contains(before.Expand(saved), "eza") || !slices.Contains(after.Expand(saved), "eza") {
		t.Fatal("new layer member must join the saved layer's expansion")
	}
}
