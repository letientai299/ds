package ds

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"maps"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/pelletier/go-toml/v2"

	"github.com/letientai299/ds/internal/assets"
)

// MisePin is the mise release ds fetches when no compatible mise exists.
type MisePin struct {
	Version string
	// Minimum is the oldest existing mise ds reuses.
	Minimum string
	// Assets maps mise platform keys to raw binaries.
	Assets map[string]Download
}

// Download is a checksummed URL.
type Download struct {
	URL    string
	SHA256 string
}

// DefaultMise pins static (musl) Linux binaries so any libc works.
var DefaultMise = MisePin{
	Version: "2026.9.12",
	Minimum: "2026.9.0",
	Assets: map[string]Download{
		"linux-arm64": {
			URL:    "https://github.com/jdx/mise/releases/download/v2026.9.12/mise-v2026.9.12-linux-arm64-musl",
			SHA256: "2d2982b12f7a13894aa88272e4cd360e68591fe105b43cff29b1ac4588c6fe83",
		},
		"linux-x64": {
			URL:    "https://github.com/jdx/mise/releases/download/v2026.9.12/mise-v2026.9.12-linux-x64-musl",
			SHA256: "e59a38683c9d776e0ea6c7b35c9829de915bb7df15d16d0bf6890afa0278bd7c",
		},
		"macos-arm64": {
			URL:    "https://github.com/jdx/mise/releases/download/v2026.9.12/mise-v2026.9.12-macos-arm64",
			SHA256: "f20d7cc555a5b0ee7b8a504acbc2583be1b0848d64115cfbe84119ceb705025b",
		},
		"macos-x64": {
			URL:    "https://github.com/jdx/mise/releases/download/v2026.9.12/mise-v2026.9.12-macos-x64",
			SHA256: "fa1e35456f1e27a4555a1ccec82d5367d7037f3b4f46d48b83c4a3bceb4d78f2",
		},
	},
}

// miseFound is an existing compatible mise.
type miseFound struct {
	Path    string
	Version string
}

// findMise returns the first compatible mise on the target's paths.
func (e *Env) findMise(ctx context.Context) (miseFound, []string) {
	var notes []string
	candidates := []string{
		filepath.Join(e.Target.Placeholders()["bin"], "mise"),
		filepath.Join(e.Target.Paths().Bin(), "mise"),
		e.fetchedMise(),
	}
	if p := lookPath("mise", e.Environ.get("PATH")); p != "" {
		candidates = append(candidates, p)
	}
	seen := map[string]bool{}
	for _, p := range candidates {
		if seen[p] || !isExecutable(p) {
			continue
		}
		seen[p] = true
		out, err := output(ctx, e.Runner, Cmd{Args: []string{p, "--version"}, Env: e.Environ})
		if err != nil {
			notes = append(notes, fmt.Sprintf("ignoring %s: %v", p, err))
			continue
		}
		version, _, _ := strings.Cut(out, " ")
		if !versionAtLeast(version, e.Mise.Minimum) {
			notes = append(notes, fmt.Sprintf("ignoring mise %s at %s (needs %s+)", version, p, e.Mise.Minimum))
			continue
		}
		return miseFound{Path: p, Version: version}, notes
	}
	return miseFound{}, notes
}

// legacyMiseNote flags MISE_CONFIG_DIR left at the Janet layout.
func (e *Env) legacyMiseNote() []string {
	p := e.Target.Paths()
	if e.Target.MiseConfigDir() != filepath.Join(p.Config, "ds", "mise") {
		return nil
	}
	return []string{fmt.Sprintf("MISE_CONFIG_DIR is the old %s; unset it to use %s", e.Target.MiseConfigDir(), filepath.Join(p.Config, "mise"))}
}

// fetchedMise is where ds stores the pinned mise.
func (e *Env) fetchedMise() string {
	return filepath.Join(e.Target.Paths().DSData(), "mise", e.Mise.Version, "mise")
}

// miseEnv isolates mise to the target's global configuration.
func (e *Env) miseEnv() envList {
	p := e.Target.Paths()
	bin := e.Target.Placeholders()["bin"]
	return e.Environ.with(
		"HOME", p.Home,
		"XDG_CONFIG_HOME", p.Config,
		"XDG_DATA_HOME", p.Data,
		"XDG_STATE_HOME", p.State,
		"XDG_CACHE_HOME", p.Cache,
		"MISE_CONFIG_DIR", e.Target.MiseConfigDir(),
		"MISE_DATA_DIR", p.MiseData,
		"MISE_CACHE_DIR", p.MiseCache,
		"MISE_STATE_DIR", p.MiseState,
		"MISE_GLOBAL_CONFIG_FILE", "",
		"MISE_GLOBAL_CONFIG_ROOT", "",
		"MISE_OVERRIDE_CONFIG_FILENAMES", "",
		"MISE_ENV", "",
		"MISE_YES", "1",
		"AUBE_ALLOWED_UNPOPULAR_PACKAGES", "git-open",
		"PATH", strings.Join([]string{bin, filepath.Join(p.MiseData, "shims"), e.Environ.get("PATH")}, ":"),
	)
}

// miseCmd runs mise outside any project configuration.
func (e *Env) miseCmd(mise string, args ...string) Cmd {
	return Cmd{
		Args:   append([]string{mise, "-C", "/"}, args...),
		Env:    e.miseEnv(),
		Dir:    "/",
		Stdout: e.Stderr,
		Stderr: e.Stderr,
		Stdin:  nil,
	}
}

func fragmentPath(t Target) string {
	return filepath.Join(t.MiseConfigDir(), "conf.d", "10-ds.toml")
}

const fragmentHeader = "# Managed by ds. Declare overrides in config.toml; it loads after this file.\n"

// renderFragment writes the tool requests of comps.
func renderFragment(cat *Catalog, comps []ComponentName, assetDir string) ([]byte, error) {
	tools := map[string]any{}
	for _, name := range comps {
		comp, _ := cat.Component(name)
		if comp.Tool == nil {
			continue
		}
		spec := substitute(comp.Tool.Spec, "{assets}", assetDir).(map[string]any)
		if len(spec) == 1 {
			tools[comp.Tool.Name] = spec["version"]
			continue
		}
		tools[comp.Tool.Name] = spec
	}
	if len(tools) == 0 {
		return nil, nil
	}
	body, err := toml.Marshal(map[string]any{"tools": tools})
	if err != nil {
		return nil, err
	}
	return append([]byte(fragmentHeader), body...), nil
}

func substitute(v any, old, replacement string) any {
	switch v := v.(type) {
	case string:
		return strings.ReplaceAll(v, old, replacement)
	case map[string]any:
		out := make(map[string]any, len(v))
		for k, item := range v {
			out[k] = substitute(item, old, replacement)
		}
		return out
	case []any:
		out := make([]any, len(v))
		for i, item := range v {
			out[i] = substitute(item, old, replacement)
		}
		return out
	}
	return v
}

// toolNames lists the mise tools owned by comps.
func toolNames(cat *Catalog, comps []ComponentName) []string {
	var names []string
	for _, name := range comps {
		if comp, _ := cat.Component(name); comp.Tool != nil {
			names = append(names, comp.Tool.Name)
		}
	}
	return names
}

// toolFact is mise's view of one effective global tool request.
type toolFact struct {
	Version     string `json:"version"`
	Requested   string `json:"requested_version"`
	Installed   bool   `json:"installed"`
	InstallPath string `json:"install_path"`
	Source      struct {
		Path string `json:"path"`
	} `json:"source"`
}

// listTools reads effective global requests without network refresh.
func (e *Env) listTools(ctx context.Context, mise string) (map[string]toolFact, error) {
	c := e.miseCmd(mise, "ls", "--global", "--json")
	c.Env = c.Env.with("MISE_OFFLINE", "1")
	out, err := output(ctx, e.Runner, c)
	if err != nil {
		return nil, err
	}
	var raw map[string][]toolFact
	if err := json.Unmarshal([]byte(out), &raw); err != nil {
		return nil, fmt.Errorf("decode mise ls: %w", err)
	}
	facts := map[string]toolFact{}
	for name, versions := range raw {
		// Installed versions without a config source are not requested.
		for _, v := range versions {
			if v.Source.Path != "" {
				facts[name] = v
				break
			}
		}
	}
	return facts, nil
}

// toolBlocker reports a tool without a download for this platform.
func toolBlocker(p Platform, comp *Component) string {
	if comp.Tool == nil {
		return ""
	}
	platforms, ok := comp.Tool.Spec["platforms"].(map[string]any)
	if !ok {
		return ""
	}
	if _, ok := platforms[p.MiseKey()]; !ok {
		keys := slices.Sorted(maps.Keys(platforms))
		return fmt.Sprintf("%s has no %s download (has %s)", comp.Tool.Name, p.MiseKey(), strings.Join(keys, ", "))
	}
	return ""
}

// download fetches url into dest after verifying its SHA-256.
func download(ctx context.Context, client *http.Client, d Download, dest string, mode os.FileMode) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, d.URL, nil)
	if err != nil {
		return err
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return &httpStatusError{URL: d.URL, Status: resp.StatusCode}
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(dest), "."+filepath.Base(dest)+".*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	hash := sha256.New()
	_, cerr := io.Copy(io.MultiWriter(tmp, hash), resp.Body)
	if err := errors.Join(cerr, tmp.Close()); err != nil {
		return fmt.Errorf("download %s: %w", d.URL, err)
	}
	if got := hex.EncodeToString(hash.Sum(nil)); got != d.SHA256 {
		return &checksumError{URL: d.URL, Want: d.SHA256, Got: got}
	}
	if err := os.Chmod(tmp.Name(), mode); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), dest)
}

type httpStatusError struct {
	URL    string
	Status int
}

func (e *httpStatusError) Error() string { return fmt.Sprintf("GET %s: HTTP %d", e.URL, e.Status) }

type checksumError struct{ URL, Want, Got string }

func (e *checksumError) Error() string {
	return fmt.Sprintf("checksum mismatch for %s: want %s, got %s", e.URL, e.Want, e.Got)
}

// assetDir is the ds asset directory referenced by tool hooks.
func (e *Env) assetDir() string { return e.assetPath(assets.Ref{Repo: assets.DS}) }
