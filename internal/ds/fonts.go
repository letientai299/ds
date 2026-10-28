package ds

import (
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/letientai299/ds/internal/assets"
)

// FontSpec pins a tar.xz font release and the files to retain from it.
type FontSpec struct {
	URL    string   `toml:"url"`
	SHA256 string   `toml:"sha256"`
	Files  []string `toml:"files"`
}

func (f FontSpec) validate() error {
	hash, err := hex.DecodeString(f.SHA256)
	if err != nil || len(hash) != 32 || f.URL == "" || len(f.Files) == 0 {
		return errors.New("font requires a URL, SHA-256, and files")
	}
	seen := map[string]bool{}
	for _, name := range f.Files {
		if name == "" || name == "." || name == ".." || strings.ContainsAny(name, `/\`) || strings.HasPrefix(name, "-") || seen[name] {
			return fmt.Errorf("invalid or duplicate font archive member %q", name)
		}
		seen[name] = true
	}
	return nil
}

// FetchFonts downloads and verifies a font release before extracting it.
type FetchFonts struct {
	Spec FontSpec
	Dir  string
	Tar  string
}

func (FetchFonts) isAction()          {}
func (a FetchFonts) Describe() string { return "download and verify fonts from " + a.Spec.URL }

func fontFilesPresent(dir string, files []string) bool {
	return len(files) > 0 && !slices.ContainsFunc(files, func(name string) bool {
		info, err := os.Lstat(filepath.Join(dir, name))
		return err != nil || !info.Mode().IsRegular() || info.Size() == 0
	})
}

func (e *Env) planFonts(p *Plan, comps []ComponentName) []managed {
	fonts, ok := e.Target.Placeholders()["fonts"]
	if !ok {
		return nil
	}
	var entries []managed
	for _, name := range comps {
		comp, _ := e.Catalog.Component(name)
		if comp.Font == nil {
			continue
		}
		spec := *comp.Font
		dir := filepath.Join(e.Target.Paths().DSData(), "fonts", spec.SHA256)
		if !fontFilesPresent(dir, spec.Files) {
			tar := lookPath("tar", e.lookupPath())
			if tar == "" {
				p.block(string(name), "tar is required to extract fonts", "install tar with xz support")
			}
			p.Actions = append(p.Actions, FetchFonts{Spec: spec, Dir: dir, Tar: tar})
		}
		for _, file := range spec.Files {
			if ext := filepath.Ext(file); ext == ".ttf" || ext == ".otf" {
				entries = append(entries, managedLink{Target: filepath.Join(fonts, file), Source: filepath.Join(dir, file)})
			}
		}
		if name == "kitty" {
			entries = append(entries, managedLink{
				Target: filepath.Join(e.Repos[assets.Kitty].Dir, "conf", "local", "ds.conf"),
				Source: e.assetPath(assets.Ref{Repo: assets.DS, Path: "dotfiles/kitty.conf"}),
			})
		}
	}
	return entries
}

func (e *Env) fetchFonts(ctx context.Context, a FetchFonts) error {
	parent := filepath.Dir(a.Dir)
	if err := os.MkdirAll(parent, 0o755); err != nil {
		return err
	}
	tmp, err := os.MkdirTemp(parent, ".fonts-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	archive := filepath.Join(tmp, "download.tar.xz")
	if err := download(ctx, e.HTTP, Download{URL: a.Spec.URL, SHA256: a.Spec.SHA256}, archive, 0o644); err != nil {
		return err
	}
	dir := filepath.Join(tmp, "files")
	if err := os.Mkdir(dir, 0o755); err != nil {
		return err
	}
	args := append([]string{a.Tar, "-xJf", archive, "-C", dir, "--"}, a.Spec.Files...)
	if err := e.Runner.Run(ctx, Cmd{Args: args, Env: e.Environ, Stderr: e.Stderr}); err != nil {
		return fmt.Errorf("extract fonts: %w", err)
	}
	if !fontFilesPresent(dir, a.Spec.Files) {
		return errors.New("font archive is missing required files")
	}
	if err := os.RemoveAll(a.Dir); err != nil {
		return err
	}
	return os.Rename(dir, a.Dir)
}
