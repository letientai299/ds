package ds

import (
	"context"
	_ "embed"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

//go:embed direnv.toml
var direnvTemplate string

// PrepareDirenv locates or initializes local mise configuration.
func PrepareDirenv(ctx context.Context, runner Runner, environ []string, dir string) (string, error) {
	root, err := rawOutput(ctx, runner, Cmd{
		Args: []string{"git", "rev-parse", "--show-toplevel"},
		Env:  NewEnviron(environ),
		Dir:  dir,
	})
	if err != nil {
		return "", fmt.Errorf("find project Git root: %w", err)
	}
	root = strings.TrimSuffix(root, "\n")
	if !filepath.IsAbs(root) {
		return "", errors.New("git root is not absolute")
	}
	path, err := localMisePath(root)
	if err != nil {
		return "", err
	}
	if exists, err := miseFileExists(path); exists || err != nil {
		return path, err
	}
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return "", fmt.Errorf("create local mise config: %w", err)
	}
	_, writeErr := f.WriteString(direnvTemplate)
	if err := errors.Join(writeErr, f.Close()); err != nil {
		return "", fmt.Errorf("initialize local mise config: %w", err)
	}
	return path, nil
}

func localMisePath(root string) (string, error) {
	layouts := [][2]string{
		{".mise.toml", ".mise.local.toml"},
		{"mise.toml", "mise.local.toml"},
		{"mise/config.toml", "mise/config.local.toml"},
		{".mise/config.toml", ".mise/config.local.toml"},
		{".config/mise.toml", ".config/mise.local.toml"},
		{".config/mise/mise.toml", ".config/mise/mise.local.toml"},
		{".config/mise/config.toml", ".config/mise/config.local.toml"},
	}
	// Preserve existing local configuration across layout changes.
	for _, layout := range layouts {
		path := filepath.Join(root, layout[1])
		if exists, err := miseFileExists(path); exists || err != nil {
			return path, err
		}
	}
	for _, layout := range layouts {
		if exists, err := miseFileExists(filepath.Join(root, layout[0])); exists || err != nil {
			return filepath.Join(root, layout[1]), err
		}
	}
	return filepath.Join(root, "mise.local.toml"), nil
}

func miseFileExists(path string) (bool, error) {
	info, err := os.Stat(path)
	if errors.Is(err, os.ErrNotExist) || errors.Is(err, syscall.ENOTDIR) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if !info.Mode().IsRegular() {
		return false, fmt.Errorf("mise config is not a file: %s", path)
	}
	return true, nil
}
