package ds

import (
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"time"

	"github.com/letientai299/ds/internal/assets"
)

// Env carries resolved inputs for domain operations. The CLI builds it at
// the boundary; domain code reads no ambient process state.
type Env struct {
	Target   Target
	Source   assets.Source
	Catalog  *Catalog
	Platform Platform
	Runner   Runner
	// Environ is the base environment for child processes.
	Environ envList
	// SystemPath extends PATH when looking for native commands, since
	// automation often runs with a minimal PATH.
	SystemPath  string
	Stdin       io.Reader
	Stdout      io.Writer
	Stderr      io.Writer
	Interactive bool
	UID         int
	Now         func() time.Time
	HTTP        *http.Client
	// DownloadURL is the base URL of published main builds.
	DownloadURL string
	Mise        MisePin
	// Executable is the running binary, staged into main builds.
	Executable string
	// Completion is the zsh completion script owned by the zsh component.
	Completion []byte
}

// NewEnviron converts os.Environ output.
func NewEnviron(kv []string) envList { return envList(kv) }

// Mode names the asset source of the running ds.
func (e *Env) Mode() string {
	switch e.Source.(type) {
	case assets.Checkout:
		return "checkout"
	case *assets.Embedded:
		return "main"
	}
	panic("unknown asset source")
}

// currentDir is the stable main-build path through the current link.
func (e *Env) currentDir() string {
	return filepath.Join(e.Target.Paths().DSData(), "current")
}

func (e *Env) buildDir(id string) string {
	return filepath.Join(e.Target.Paths().DSData(), "builds", id)
}

// assetPath is the on-disk path that links should reference.
func (e *Env) assetPath(ref assets.Ref) string {
	switch src := e.Source.(type) {
	case assets.Checkout:
		return src.Path(ref)
	case *assets.Embedded:
		return filepath.Join(e.currentDir(), "assets", string(ref.Repo), filepath.FromSlash(ref.Path))
	}
	panic("unknown asset source")
}

// sourceAvailable reports whether ref exists in the asset source.
func (e *Env) sourceAvailable(ref assets.Ref) bool {
	switch src := e.Source.(type) {
	case assets.Checkout:
		p := src.Path(ref)
		return p != "" && exists(p)
	case *assets.Embedded:
		return src.Has(ref)
	}
	return false
}

// dsExecutable is what {bin}/ds links to.
func (e *Env) dsExecutable() string {
	switch src := e.Source.(type) {
	case assets.Checkout:
		return src.Launcher()
	case *assets.Embedded:
		return filepath.Join(e.currentDir(), "ds")
	}
	panic("unknown asset source")
}

// legacyRoots are link destinations that prove ds ownership.
func (e *Env) legacyRoots() []string {
	p := e.Target.Paths()
	// ds-source is the Janet installer's checkout prefix.
	roots := []string{p.DSData(), filepath.Join(p.Data, "ds-source")}
	if src, ok := e.Source.(assets.Checkout); ok {
		roots = append(roots, src.Root)
		for _, p := range src.Repos {
			roots = append(roots, p)
		}
	}
	return roots
}

// LoadCatalog reads and validates the catalog of src.
func LoadCatalog(src assets.Source) (*Catalog, error) {
	data, err := src.ReadFile(assets.Ref{Repo: assets.DS, Path: "catalog.toml"})
	if err != nil {
		return nil, fmt.Errorf("read catalog: %w", err)
	}
	return ParseCatalog(data)
}

func (e *Env) now() time.Time {
	if e.Now != nil {
		return e.Now()
	}
	return time.Now()
}

func (e *Env) printf(format string, args ...any) {
	fmt.Fprintf(e.Stderr, format, args...)
}
