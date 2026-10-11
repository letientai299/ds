package ds

import (
	"bytes"
	"errors"
	"fmt"
	"io/fs"
	"os"

	"github.com/pelletier/go-toml/v2"

	"github.com/letientai299/ds/internal/assets"
)

// UserConfig is <config>/ds/config.toml, edited by the user.
type UserConfig struct {
	// Sources place configuration repository checkouts.
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
