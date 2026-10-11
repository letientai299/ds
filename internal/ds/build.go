package ds

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/letientai299/ds/internal/assets"
)

// A main build directory holds ds, assets/<repo>, and build.json, which is
// written last and marks the directory complete.
const buildMeta = "build.json"

func buildComplete(dir string) bool {
	_, err := os.Stat(filepath.Join(dir, buildMeta))
	return err == nil
}

// currentBuild returns the build ID that the current link names.
func currentBuild(dataDir string) string {
	dest, err := os.Readlink(filepath.Join(dataDir, "current"))
	if err != nil {
		return ""
	}
	id, ok := strings.CutPrefix(dest, "builds/")
	if !ok {
		return ""
	}
	return id
}

// stageBuild copies the executable and extracts embedded assets into dir
// through a sibling temporary directory and a rename.
func stageBuild(emb *assets.Embedded, executable, dir string) error {
	parent := filepath.Dir(dir)
	if err := os.MkdirAll(parent, 0o755); err != nil {
		return err
	}
	tmp, err := os.MkdirTemp(parent, "."+filepath.Base(dir)+".")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	if err := os.Chmod(tmp, 0o755); err != nil {
		return err
	}
	if err := emb.Extract(filepath.Join(tmp, "assets")); err != nil {
		return fmt.Errorf("extract assets: %w", err)
	}
	if err := copyFile(executable, filepath.Join(tmp, "ds"), 0o755); err != nil {
		return fmt.Errorf("copy executable: %w", err)
	}
	meta, err := json.MarshalIndent(emb.Info, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(tmp, buildMeta), append(meta, '\n'), 0o644); err != nil {
		return err
	}
	// An incomplete earlier attempt is replaced.
	if err := os.RemoveAll(dir); err != nil {
		return err
	}
	return os.Rename(tmp, dir)
}

// activateBuild points current at id and prunes builds other than the new
// and previous ones.
func activateBuild(dataDir, id string) error {
	previous := currentBuild(dataDir)
	link := filepath.Join(dataDir, "current")
	tmp := filepath.Join(dataDir, ".current.new")
	os.Remove(tmp)
	if err := os.Symlink(filepath.Join("builds", id), tmp); err != nil {
		return err
	}
	if err := os.Rename(tmp, link); err != nil {
		os.Remove(tmp)
		return err
	}
	entries, err := os.ReadDir(filepath.Join(dataDir, "builds"))
	if err != nil {
		return err
	}
	var errs []error
	for _, entry := range entries {
		name := entry.Name()
		if name == id || name == previous {
			continue
		}
		errs = append(errs, os.RemoveAll(filepath.Join(dataDir, "builds", name)))
	}
	return errors.Join(errs...)
}

func copyFile(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	_, err = io.Copy(out, in)
	return errors.Join(err, out.Close())
}
