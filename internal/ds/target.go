package ds

import (
	"errors"
	"fmt"
	"path/filepath"
	"strings"
)

// Paths holds the resolved directories of one home.
type Paths struct {
	Home   string
	Config string
	Data   string
	State  string
	Cache  string

	MiseConfig string
	MiseData   string
	MiseCache  string
	MiseState  string

	// CursorConfig is the directory that holds cli-config.json.
	CursorConfig string
}

// Getenv reads an environment variable.
type Getenv func(string) string

// ResolvePaths derives paths from HOME and XDG settings, or entirely from an
// explicit home so inherited variables cannot redirect writes elsewhere.
func ResolvePaths(getenv Getenv, explicitHome string) (Paths, error) {
	if explicitHome != "" {
		home, err := absHome(explicitHome, getenv("HOME"))
		if err != nil {
			return Paths{}, err
		}
		return homePaths(home), nil
	}
	home := getenv("HOME")
	if home == "" || !filepath.IsAbs(home) {
		return Paths{}, errors.New("HOME must be an absolute path")
	}
	p := homePaths(filepath.Clean(home))
	xdg := func(key, fallback string) string {
		if v := getenv(key); filepath.IsAbs(v) {
			return filepath.Clean(v)
		}
		return fallback
	}
	p.Config = xdg("XDG_CONFIG_HOME", p.Config)
	p.Data = xdg("XDG_DATA_HOME", p.Data)
	p.State = xdg("XDG_STATE_HOME", p.State)
	p.Cache = xdg("XDG_CACHE_HOME", p.Cache)
	p.MiseConfig = xdg("MISE_CONFIG_DIR", filepath.Join(p.Config, "mise"))
	p.MiseData = xdg("MISE_DATA_DIR", filepath.Join(p.Data, "mise"))
	p.MiseCache = xdg("MISE_CACHE_DIR", filepath.Join(p.Cache, "mise"))
	p.MiseState = xdg("MISE_STATE_DIR", filepath.Join(p.State, "mise"))
	if v := getenv("CURSOR_CONFIG_DIR"); filepath.IsAbs(v) {
		p.CursorConfig = filepath.Clean(v)
	} else if v := getenv("XDG_CONFIG_HOME"); filepath.IsAbs(v) {
		p.CursorConfig = filepath.Join(filepath.Clean(v), "cursor")
	}
	return p, nil
}

func homePaths(home string) Paths {
	p := Paths{
		Home:   home,
		Config: filepath.Join(home, ".config"),
		Data:   filepath.Join(home, ".local", "share"),
		State:  filepath.Join(home, ".local", "state"),
		Cache:  filepath.Join(home, ".cache"),
	}
	p.MiseConfig = filepath.Join(p.Config, "mise")
	p.MiseData = filepath.Join(p.Data, "mise")
	p.MiseCache = filepath.Join(p.Cache, "mise")
	p.MiseState = filepath.Join(p.State, "mise")
	p.CursorConfig = filepath.Join(home, ".cursor")
	return p
}

// absHome resolves ~ and relative paths against the login home.
func absHome(p, login string) (string, error) {
	if p == "~" || strings.HasPrefix(p, "~/") {
		if login == "" {
			return "", errors.New("HOME is required to expand ~")
		}
		p = filepath.Join(login, strings.TrimPrefix(p, "~"))
	}
	if !filepath.IsAbs(p) {
		if login == "" || !filepath.IsAbs(login) {
			return "", fmt.Errorf("cannot resolve relative home %q without HOME", p)
		}
		p = filepath.Join(login, p)
	}
	return filepath.Clean(p), nil
}

// Bin is the per-user executable directory.
func (p Paths) Bin() string { return filepath.Join(p.Home, ".local", "bin") }

// DSData holds main builds and the fetched mise binary.
func (p Paths) DSData() string { return filepath.Join(p.Data, "ds") }

// UserConfig is the user-edited ds configuration file.
func (p Paths) UserConfig() string { return filepath.Join(p.Config, "ds", "config.toml") }

// Target is where ds converges configuration: a home or a trial.
type Target interface {
	Paths() Paths
	// Placeholders map catalog target keys to paths; a missing key skips
	// entries that use it.
	Placeholders() map[string]string
	StateDir() string
	MiseConfigDir() string
	NvimAppName() string
	isTarget()
}

// HomeTarget converges a user's real configuration.
type HomeTarget struct {
	P  Paths
	OS string
}

// TrialTarget converges an isolated trial beneath the state directory.
type TrialTarget struct{ P Paths }

func (HomeTarget) isTarget()  {}
func (TrialTarget) isTarget() {}

func (t HomeTarget) Paths() Paths           { return t.P }
func (t HomeTarget) StateDir() string       { return filepath.Join(t.P.State, "ds") }
func (t HomeTarget) MiseConfigDir() string  { return t.P.MiseConfig }
func (HomeTarget) NvimAppName() string      { return "nvim" }
func (t TrialTarget) Paths() Paths          { return t.P }
func (t TrialTarget) Root() string          { return filepath.Join(t.P.State, "ds", "trial") }
func (t TrialTarget) StateDir() string      { return t.Root() }
func (t TrialTarget) MiseConfigDir() string { return filepath.Join(t.Root(), "mise") }
func (TrialTarget) NvimAppName() string     { return "ds-trial-nvim" }
func (t TrialTarget) Bin() string           { return filepath.Join(t.Root(), "bin") }
func (t TrialTarget) ZDotDir() string       { return filepath.Join(t.Root(), "zsh") }
func (t TrialTarget) GitConfig() string     { return filepath.Join(t.Root(), "gitconfig") }
func (t TrialTarget) DSConfigDir() string   { return filepath.Join(t.Root(), "ds") }
func (t TrialTarget) TmuxConfigDir() string { return filepath.Join(t.Root(), "tmux") }

func (t HomeTarget) Placeholders() map[string]string {
	fonts := filepath.Join(t.P.Data, "fonts")
	if t.OS == "darwin" {
		fonts = filepath.Join(t.P.Home, "Library", "Fonts")
	}
	return map[string]string{
		"fonts":     fonts,
		"bin":       t.P.Bin(),
		"ds":        filepath.Join(t.P.Config, "ds"),
		"zshrc":     filepath.Join(t.P.Home, ".zshrc"),
		"gitconfig": filepath.Join(t.P.Home, ".gitconfig"),
		"ssh":       filepath.Join(t.P.Home, ".ssh", "config"),
		"nvim":      filepath.Join(t.P.Config, "nvim"),
		"tmux":      filepath.Join(t.P.Config, "tmux"),
		"claude":    filepath.Join(t.P.Home, ".claude"),
		"cursor":    t.P.CursorConfig,
	}
}

func (t TrialTarget) Placeholders() map[string]string {
	return map[string]string{
		"bin":       t.Bin(),
		"ds":        t.DSConfigDir(),
		"zshrc":     filepath.Join(t.ZDotDir(), ".zshrc"),
		"gitconfig": t.GitConfig(),
		"nvim":      filepath.Join(t.P.Config, t.NvimAppName()),
		"tmux":      t.TmuxConfigDir(),
	}
}

// expand substitutes a catalog placeholder; ok is false when the target
// does not provide it.
func expand(t Target, pattern string) (string, bool) {
	m := targetPattern.FindStringSubmatch(pattern)
	if m == nil {
		return "", false
	}
	base, ok := t.Placeholders()[m[1]]
	if !ok {
		return "", false
	}
	return filepath.Join(base, filepath.FromSlash(strings.TrimPrefix(m[2], "/"))), true
}

// expandText substitutes {key} placeholders inside block text.
func expandText(t Target, text string) string {
	for key, value := range t.Placeholders() {
		text = strings.ReplaceAll(text, "{"+key+"}", value)
	}
	return text
}

// expandValue substitutes placeholders in every string of a decoded value.
func expandValue(t Target, v any) any {
	switch v := v.(type) {
	case string:
		return expandText(t, v)
	case map[string]any:
		out := make(map[string]any, len(v))
		for key, item := range v {
			out[key] = expandValue(t, item)
		}
		return out
	case []any:
		out := make([]any, len(v))
		for i, item := range v {
			out[i] = expandValue(t, item)
		}
		return out
	}
	return v
}

// lockPath is the advisory lock file of a target.
func lockPath(t Target) string { return filepath.Join(t.StateDir(), "lock") }

func statePath(t Target) string { return filepath.Join(t.StateDir(), "state.json") }

func describeTarget(t Target) string {
	switch t := t.(type) {
	case TrialTarget:
		return "trial " + t.Root()
	case HomeTarget:
		return "home " + t.P.Home
	}
	panic("unknown target")
}
