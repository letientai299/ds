// Package assets provides ds configuration assets from a live checkout or
// from the snapshot embedded in a main build.
package assets

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"slices"
	"strings"
	"sync"
)

// Repo names an asset repository.
type Repo string

// Asset repositories. DS is this repository's assets directory.
const (
	DS    Repo = "ds"
	Nvim  Repo = "nvim"
	Tmux  Repo = "tmux"
	Kitty Repo = "kitty"
)

// ConfigRepos are the separately versioned configuration repositories.
var ConfigRepos = []Repo{Nvim, Tmux, Kitty}

// Valid reports whether r is a known repository.
func (r Repo) Valid() bool { return r == DS || slices.Contains(ConfigRepos, r) }

// CheckoutName is the conventional sibling checkout directory name.
func (r Repo) CheckoutName() string { return string(r) + ".conf" }

// Ref names a path inside an asset repository. An empty path is the root.
type Ref struct {
	Repo Repo
	Path string
}

// ParseRef parses "repo:path".
func ParseRef(s string) (Ref, error) {
	repo, p, ok := strings.Cut(s, ":")
	ref := Ref{Repo: Repo(repo), Path: p}
	if !ok || !ref.Repo.Valid() || (p != "" && !fs.ValidPath(p)) {
		return Ref{}, fmt.Errorf("invalid asset reference %q", s)
	}
	return ref, nil
}

func (r Ref) String() string { return string(r.Repo) + ":" + r.Path }

func (r Ref) archivePath() string {
	if r.Path == "" {
		return string(r.Repo)
	}
	return string(r.Repo) + "/" + r.Path
}

// Revision records the source of one repository in a build.
type Revision struct {
	URL    string `json:"url,omitempty"`
	Commit string `json:"commit"`
	Dirty  bool   `json:"dirty,omitempty"`
}

// Workflow records the CI run that produced a build.
type Workflow struct {
	RunID      int64  `json:"run_id"`
	RunAttempt int    `json:"run_attempt,omitempty"`
	URL        string `json:"url,omitempty"`
}

// BuildInfo identifies a main build and its embedded configuration.
type BuildInfo struct {
	Schema   int               `json:"schema"`
	ID       string            `json:"id"`
	Platform string            `json:"platform"`
	Commit   string            `json:"commit"`
	Dirty    bool              `json:"dirty,omitempty"`
	Workflow *Workflow         `json:"workflow,omitempty"`
	Sources  map[Repo]Revision `json:"sources"`
}

// Source supplies ds assets. Checkout and Embedded are its variants.
type Source interface {
	ReadFile(ref Ref) ([]byte, error)
	isSource()
}

// Checkout reads live assets from a source checkout and configuration
// repositories.
type Checkout struct {
	Root  string
	Repos map[Repo]string
}

func (Checkout) isSource() {}

// Path returns the live filesystem path of ref, or "" when its repository
// is not configured.
func (c Checkout) Path(ref Ref) string {
	base := c.Repos[ref.Repo]
	if ref.Repo == DS {
		base = filepath.Join(c.Root, "assets")
	}
	if base == "" {
		return ""
	}
	return filepath.Join(base, filepath.FromSlash(ref.Path))
}

// Launcher is the checkout's POSIX entrypoint.
func (c Checkout) Launcher() string { return filepath.Join(c.Root, "ds") }

// ReadFile reads a live asset.
func (c Checkout) ReadFile(ref Ref) ([]byte, error) {
	p := c.Path(ref)
	if p == "" {
		return nil, fmt.Errorf("%s source is not configured", ref.Repo)
	}
	return os.ReadFile(p)
}

// Embedded reads the gzip tar snapshot compiled into a main build.
type Embedded struct {
	Info    BuildInfo
	archive []byte

	once  sync.Once
	index map[string]*tar.Header
	data  map[string][]byte
	err   error
}

func (*Embedded) isSource() {}

// NewEmbedded validates build metadata and wraps a snapshot archive.
func NewEmbedded(buildJSON, archive []byte) (*Embedded, error) {
	var info BuildInfo
	if err := json.Unmarshal(buildJSON, &info); err != nil {
		return nil, fmt.Errorf("decode build metadata: %w", err)
	}
	if info.Schema != 1 || info.ID == "" || !validID(info.ID) {
		return nil, errors.New("invalid build metadata")
	}
	return &Embedded{Info: info, archive: archive}, nil
}

// Default returns the snapshot compiled into this binary, if any.
func Default() (*Embedded, error) {
	if len(buildJSON) == 0 {
		return nil, nil
	}
	return NewEmbedded(buildJSON, archiveData)
}

func validID(id string) bool {
	return id != "" && strings.Trim(id, "0123456789abcdefghijklmnopqrstuvwxyz-") == "" && !strings.HasPrefix(id, "-")
}

func (e *Embedded) load() error {
	e.once.Do(func() {
		e.index = map[string]*tar.Header{}
		e.data = map[string][]byte{}
		e.err = walkArchive(e.archive, func(h *tar.Header, r io.Reader) error {
			e.index[strings.TrimSuffix(h.Name, "/")] = h
			if h.Typeflag == tar.TypeReg {
				b, err := io.ReadAll(r)
				if err != nil {
					return err
				}
				e.data[h.Name] = b
			}
			return nil
		})
	})
	return e.err
}

// Has reports whether the snapshot contains ref.
func (e *Embedded) Has(ref Ref) bool {
	if e.load() != nil {
		return false
	}
	_, ok := e.index[ref.archivePath()]
	return ok
}

// ReadFile reads a regular file from the snapshot.
func (e *Embedded) ReadFile(ref Ref) ([]byte, error) {
	if err := e.load(); err != nil {
		return nil, err
	}
	b, ok := e.data[ref.archivePath()]
	if !ok {
		return nil, fmt.Errorf("%s: %w", ref, fs.ErrNotExist)
	}
	return b, nil
}

// Extract writes the snapshot under dir, one directory per repository.
func (e *Embedded) Extract(dir string) error {
	return walkArchive(e.archive, func(h *tar.Header, r io.Reader) error {
		target := filepath.Join(dir, filepath.FromSlash(strings.TrimSuffix(h.Name, "/")))
		switch h.Typeflag {
		case tar.TypeDir:
			return os.MkdirAll(target, 0o755)
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			mode := fs.FileMode(0o644)
			if h.Mode&0o111 != 0 {
				mode = 0o755
			}
			f, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_EXCL, mode)
			if err != nil {
				return err
			}
			_, err = io.Copy(f, r)
			return errors.Join(err, f.Close())
		case tar.TypeSymlink:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			return os.Symlink(h.Linkname, target)
		}
		return fmt.Errorf("unsupported archive entry %s", h.Name)
	})
}

func walkArchive(archive []byte, visit func(*tar.Header, io.Reader) error) error {
	gz, err := gzip.NewReader(bytes.NewReader(archive))
	if err != nil {
		return fmt.Errorf("open asset archive: %w", err)
	}
	tr := tar.NewReader(gz)
	for {
		h, err := tr.Next()
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("read asset archive: %w", err)
		}
		name := strings.TrimSuffix(h.Name, "/")
		if !fs.ValidPath(name) || name == "." {
			return fmt.Errorf("unsafe archive entry %q", h.Name)
		}
		if h.Typeflag == tar.TypeSymlink && !SafeLink(name, h.Linkname) {
			return fmt.Errorf("unsafe archive link %q -> %q", h.Name, h.Linkname)
		}
		if err := visit(h, tr); err != nil {
			return err
		}
	}
}

// SafeLink reports whether a relative symlink at archive path name stays
// inside its repository.
func SafeLink(name, target string) bool {
	if path.IsAbs(target) {
		return false
	}
	repo, _, _ := strings.Cut(name, "/")
	resolved := path.Join(path.Dir(name), target)
	return resolved == repo || strings.HasPrefix(resolved, repo+"/")
}
