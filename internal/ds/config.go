package ds

import (
	"bytes"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/pelletier/go-toml/v2"

	"github.com/letientai299/ds/internal/assets"
)

// UserConfig is <config>/ds/config.toml, edited by the user.
type UserConfig struct {
	// Sources select live configuration checkouts in checkout mode.
	Sources map[string]string `toml:"sources"`
	// DownloadURL overrides where main builds are published.
	DownloadURL string `toml:"download_url"`
}

// LoadUserConfig reads the user configuration; a missing file is empty.
func LoadUserConfig(p Paths) (UserConfig, error) {
	var c UserConfig
	data, err := os.ReadFile(p.UserConfig())
	if errors.Is(err, fs.ErrNotExist) {
		return c, nil
	}
	if err != nil {
		return c, err
	}
	dec := toml.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&c); err != nil {
		return c, fmt.Errorf("decode %s: %w", p.UserConfig(), err)
	}
	for name := range c.Sources {
		if repo := assets.Repo(name); !repo.Valid() || repo == assets.DS {
			return c, fmt.Errorf("%s: unknown source %q", p.UserConfig(), name)
		}
	}
	return c, nil
}

// CheckoutRepos resolves configuration repositories for a checkout:
// configured paths first, then siblings of the checkout, then the snapshot
// of an installed main build so a checkout reuses a prebuilt provision.
func (c UserConfig) CheckoutRepos(root string, p Paths) (map[assets.Repo]string, error) {
	repos := map[assets.Repo]string{}
	for _, repo := range assets.ConfigRepos {
		if configured := c.Sources[string(repo)]; configured != "" {
			abs, err := absHome(configured, p.Home)
			if err != nil {
				return nil, err
			}
			repos[repo] = abs
			continue
		}
		dir := filepath.Join(filepath.Dir(root), repo.CheckoutName())
		if snapshot := buildSnapshot(p, repo); !exists(dir) && exists(snapshot) {
			dir = snapshot
		}
		repos[repo] = dir
	}
	return repos, nil
}

// buildSnapshot is repo's tree in the active main build.
func buildSnapshot(p Paths, repo assets.Repo) string {
	return filepath.Join(p.DSData(), "current", "assets", string(repo))
}
