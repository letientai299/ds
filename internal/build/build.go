// Package build exports configuration snapshots and produces main builds.
package build

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"debug/elf"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"maps"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"slices"
	"strconv"
	"strings"

	"github.com/letientai299/ds/internal/assets"
)

// Platforms are the published main-build targets.
var Platforms = []string{"darwin/arm64", "darwin/amd64", "linux/arm64", "linux/amd64"}

// Options select the inputs of a snapshot.
type Options struct {
	// Root is the ds checkout.
	Root string
	// Sources are configuration repository checkouts.
	Sources map[assets.Repo]string
	// Workflow identifies the CI run, when there is one.
	Workflow *assets.Workflow
}

// entry is one exported file.
type entry struct {
	name string // archive path: <repo>/<path>
	mode int64
	link string
	data []byte
}

// Snapshot is the platform-independent export of every repository.
type Snapshot struct {
	Info    assets.BuildInfo
	entries []entry
	// source digests every ds file so code changes alter the build ID.
	source string
}

// Collect exports tracked and untracked, non-ignored files of ds assets and
// the configuration repositories.
func Collect(ctx context.Context, opt Options) (*Snapshot, error) {
	s := &Snapshot{Info: assets.BuildInfo{Schema: 1, Sources: map[assets.Repo]assets.Revision{}, Workflow: opt.Workflow}}
	rev, err := revision(ctx, opt.Root)
	if err != nil {
		return nil, err
	}
	s.Info.Commit, s.Info.Dirty = rev.Commit, rev.Dirty
	if err := s.add(ctx, assets.DS, opt.Root, "assets"); err != nil {
		return nil, err
	}
	if s.source, err = sourceDigest(ctx, opt.Root); err != nil {
		return nil, err
	}
	for _, repo := range assets.ConfigRepos {
		dir := opt.Sources[repo]
		if dir == "" {
			return nil, fmt.Errorf("%s source is required", repo)
		}
		rev, err := revision(ctx, dir)
		if err != nil {
			return nil, err
		}
		s.Info.Sources[repo] = rev
		if err := s.add(ctx, repo, dir, ""); err != nil {
			return nil, err
		}
	}
	slices.SortFunc(s.entries, func(a, b entry) int { return strings.Compare(a.name, b.name) })
	s.Info.ID = s.id()
	return s, nil
}

func git(ctx context.Context, dir string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, "git", append([]string{"-C", dir}, args...)...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("git %s in %s: %w: %s", strings.Join(args, " "), dir, err, strings.TrimSpace(stderr.String()))
	}
	return string(out), nil
}

func revision(ctx context.Context, dir string) (assets.Revision, error) {
	commit, err := git(ctx, dir, "rev-parse", "HEAD")
	if err != nil {
		return assets.Revision{}, err
	}
	status, err := git(ctx, dir, "status", "--porcelain")
	if err != nil {
		return assets.Revision{}, err
	}
	url, _ := git(ctx, dir, "remote", "get-url", "origin")
	return assets.Revision{URL: strings.TrimSpace(url), Commit: strings.TrimSpace(commit), Dirty: status != ""}, nil
}

// add exports files of dir below prefix as <repo>/<relative path>.
func (s *Snapshot) add(ctx context.Context, repo assets.Repo, dir, prefix string) error {
	args := []string{"ls-files", "-z", "--cached", "--others", "--exclude-standard"}
	if prefix != "" {
		args = append(args, "--", prefix)
	}
	out, err := git(ctx, dir, args...)
	if err != nil {
		return err
	}
	seen := map[string]bool{}
	for _, rel := range strings.Split(out, "\x00") {
		if rel == "" || seen[rel] {
			continue
		}
		seen[rel] = true
		p := filepath.Join(dir, filepath.FromSlash(rel))
		info, err := os.Lstat(p)
		if errors.Is(err, fs.ErrNotExist) {
			continue // deleted in the working tree
		}
		if err != nil {
			return err
		}
		name := string(repo) + "/" + strings.TrimPrefix(strings.TrimPrefix(rel, prefix), "/")
		e := entry{name: name, mode: 0o644}
		switch {
		case info.Mode()&fs.ModeSymlink != 0:
			if e.link, err = os.Readlink(p); err != nil {
				return err
			}
			if !assets.SafeLink(name, e.link) {
				return fmt.Errorf("%s links outside its repository: %s", p, e.link)
			}
		case info.Mode().IsRegular():
			if info.Mode().Perm()&0o111 != 0 {
				e.mode = 0o755
			}
			if e.data, err = os.ReadFile(p); err != nil {
				return err
			}
		default:
			continue // submodules and other special entries
		}
		s.entries = append(s.entries, e)
	}
	return nil
}

// sourceDigest hashes tracked and untracked, non-ignored files of root.
func sourceDigest(ctx context.Context, root string) (string, error) {
	out, err := git(ctx, root, "ls-files", "-z", "--cached", "--others", "--exclude-standard")
	if err != nil {
		return "", err
	}
	names := strings.Split(out, "\x00")
	slices.Sort(names)
	h := sha256.New()
	for _, name := range slices.Compact(names) {
		data, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(name)))
		if name == "" || errors.Is(err, fs.ErrNotExist) {
			continue
		}
		if err != nil {
			return "", err
		}
		fmt.Fprintf(h, "%s %x\n", name, sha256.Sum256(data))
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// id derives a stable build identity from sources and exported content.
func (s *Snapshot) id() string {
	h := sha256.New()
	fmt.Fprintf(h, "ds %s %t %s\n", s.Info.Commit, s.Info.Dirty, s.source)
	for _, repo := range slices.Sorted(maps.Keys(s.Info.Sources)) {
		rev := s.Info.Sources[repo]
		fmt.Fprintf(h, "%s %s %t\n", repo, rev.Commit, rev.Dirty)
	}
	for _, e := range s.entries {
		sum := sha256.Sum256(e.data)
		fmt.Fprintf(h, "%s %o %s %x\n", e.name, e.mode, e.link, sum)
	}
	commit := s.Info.Commit
	if len(commit) > 7 {
		commit = commit[:7]
	}
	return commit + "-" + hex.EncodeToString(h.Sum(nil))[:10]
}

const helperName = "kitty/bin/kt"

// WriteEmbedded writes build.json and assets.tar.gz for one platform into
// dir, adding the platform's compiled helper.
func (s *Snapshot) WriteEmbedded(dir, platform string, helper []byte) error {
	info := s.Info
	info.Platform = platform
	meta, err := json.MarshalIndent(info, "", "  ")
	if err != nil {
		return err
	}
	entries := slices.Clone(s.entries)
	if helper != nil {
		// The compiled helper replaces any checked-in binary.
		entries = slices.DeleteFunc(entries, func(e entry) bool { return e.name == helperName })
		entries = append(entries, entry{name: helperName, mode: 0o755, data: helper})
		slices.SortFunc(entries, func(a, b entry) int { return strings.Compare(a.name, b.name) })
	}
	archive, err := tarball(entries)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(dir, "build.json"), append(meta, '\n'), 0o644); err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "assets.tar.gz"), archive, 0o644)
}

// tarball writes a deterministic gzip tar with parent directories.
func tarball(entries []entry) ([]byte, error) {
	var buf bytes.Buffer
	gz, _ := gzip.NewWriterLevel(&buf, gzip.BestCompression)
	tw := tar.NewWriter(gz)
	dirs := map[string]bool{}
	var mkdirs func(string) error
	mkdirs = func(d string) error {
		if d == "." || dirs[d] {
			return nil
		}
		if err := mkdirs(path.Dir(d)); err != nil {
			return err
		}
		dirs[d] = true
		return tw.WriteHeader(&tar.Header{Typeflag: tar.TypeDir, Name: d + "/", Mode: 0o755, Format: tar.FormatPAX})
	}
	for _, e := range entries {
		if err := mkdirs(path.Dir(e.name)); err != nil {
			return nil, err
		}
		h := &tar.Header{Name: e.name, Mode: e.mode, Format: tar.FormatPAX}
		if e.link != "" {
			h.Typeflag, h.Linkname, h.Mode = tar.TypeSymlink, e.link, 0o777
		} else {
			h.Typeflag, h.Size = tar.TypeReg, int64(len(e.data))
		}
		if err := tw.WriteHeader(h); err != nil {
			return nil, err
		}
		if _, err := tw.Write(e.data); err != nil {
			return nil, err
		}
	}
	if err := errors.Join(tw.Close(), gz.Close()); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// BuildHelper compiles the Kitty helper for platform.
func BuildHelper(ctx context.Context, kittyDir, platform, out string) ([]byte, error) {
	goos, goarch, _ := strings.Cut(platform, "/")
	cmd := exec.CommandContext(ctx, "go", "build", "-trimpath", "-ldflags", "-s -w", "-o", out, "./cmd/kt")
	cmd.Dir = kittyDir
	cmd.Env = append(os.Environ(), "CGO_ENABLED=0", "GOOS="+goos, "GOARCH="+goarch, "GOFLAGS=-mod=readonly")
	cmd.Stdout, cmd.Stderr = os.Stderr, os.Stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("build kitty helper for %s: %w", platform, err)
	}
	return os.ReadFile(out)
}

// BuildBinary compiles ds with the embedded snapshot for platform.
func BuildBinary(ctx context.Context, root, platform, out string) error {
	goos, goarch, _ := strings.Cut(platform, "/")
	cmd := exec.CommandContext(ctx, "go", "build", "-tags", "dsembed", "-trimpath", "-ldflags", "-s -w", "-o", out, "./cmd/ds")
	cmd.Dir = root
	cmd.Env = append(os.Environ(), "CGO_ENABLED=0", "GOOS="+goos, "GOARCH="+goarch)
	cmd.Stdout, cmd.Stderr = os.Stderr, os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("build ds for %s: %w", platform, err)
	}
	return nil
}

// Manifest mirrors the published manifest.
type Manifest struct {
	Schema   int                             `json:"schema"`
	Build    string                          `json:"build"`
	Commit   string                          `json:"commit"`
	Sources  map[assets.Repo]assets.Revision `json:"sources"`
	Workflow *assets.Workflow                `json:"workflow,omitempty"`
	Files    map[string]ManifestFile         `json:"files"`
}

// ManifestFile is one published binary.
type ManifestFile struct {
	Name   string `json:"name"`
	SHA256 string `json:"sha256"`
	Size   int64  `json:"size"`
}

// Dist builds every platform into out with manifest.json, latest.tsv, and
// the bootstrap script.
func Dist(ctx context.Context, opt Options, out string, platforms []string) (Manifest, error) {
	s, err := Collect(ctx, opt)
	if err != nil {
		return Manifest{}, err
	}
	m := Manifest{Schema: 1, Build: s.Info.ID, Commit: s.Info.Commit, Sources: s.Info.Sources, Workflow: opt.Workflow, Files: map[string]ManifestFile{}}
	if err := os.MkdirAll(out, 0o755); err != nil {
		return m, err
	}
	embedded := filepath.Join(opt.Root, "internal", "assets", "embedded")
	defer os.RemoveAll(embedded)
	work, err := os.MkdirTemp("", "ds-dist-")
	if err != nil {
		return m, err
	}
	defer os.RemoveAll(work)
	for _, platform := range platforms {
		helper, err := BuildHelper(ctx, opt.Sources[assets.Kitty], platform, filepath.Join(work, "kt-"+strings.ReplaceAll(platform, "/", "-")))
		if err != nil {
			return m, err
		}
		if err := s.WriteEmbedded(embedded, platform, helper); err != nil {
			return m, err
		}
		name := fmt.Sprintf("ds-%s-%s", s.Info.ID, strings.ReplaceAll(platform, "/", "-"))
		bin := filepath.Join(out, name)
		if err := BuildBinary(ctx, opt.Root, platform, bin); err != nil {
			return m, err
		}
		data, err := os.ReadFile(bin)
		if err != nil {
			return m, err
		}
		sum := sha256.Sum256(data)
		m.Files[platform] = ManifestFile{Name: name, SHA256: hex.EncodeToString(sum[:]), Size: int64(len(data))}
	}
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return m, err
	}
	if err := os.WriteFile(filepath.Join(out, "manifest.json"), append(data, '\n'), 0o644); err != nil {
		return m, err
	}
	var tsv strings.Builder
	fmt.Fprintf(&tsv, "# build %s commit %s\n", m.Build, m.Commit)
	for _, platform := range slices.Sorted(maps.Keys(m.Files)) {
		f := m.Files[platform]
		fmt.Fprintf(&tsv, "%s\t%s\t%s\n", platform, f.Name, f.SHA256)
	}
	if err := os.WriteFile(filepath.Join(out, "latest.tsv"), []byte(tsv.String()), 0o644); err != nil {
		return m, err
	}
	boot, err := os.ReadFile(filepath.Join(opt.Root, "assets", "bootstrap.sh"))
	if err != nil {
		return m, err
	}
	return m, os.WriteFile(filepath.Join(out, "bootstrap.sh"), boot, 0o755)
}

// CheckStatic rejects Linux executables with a dynamic loader or shared
// library dependencies.
func CheckStatic(p string) error {
	f, err := elf.Open(p)
	if err != nil {
		return fmt.Errorf("%s: %w", p, err)
	}
	defer f.Close()
	for _, prog := range f.Progs {
		if prog.Type == elf.PT_INTERP {
			return fmt.Errorf("%s requests a dynamic loader", p)
		}
	}
	if libs, err := f.ImportedLibraries(); err == nil && len(libs) > 0 {
		return fmt.Errorf("%s needs shared libraries: %s", p, strings.Join(libs, ", "))
	}
	return nil
}

// WorkflowFromEnv reads GitHub Actions run identity.
func WorkflowFromEnv(getenv func(string) string) *assets.Workflow {
	id, err := strconv.ParseInt(getenv("GITHUB_RUN_ID"), 10, 64)
	if err != nil {
		return nil
	}
	attempt, _ := strconv.Atoi(getenv("GITHUB_RUN_ATTEMPT"))
	url := fmt.Sprintf("%s/%s/actions/runs/%d", getenv("GITHUB_SERVER_URL"), getenv("GITHUB_REPOSITORY"), id)
	return &assets.Workflow{RunID: id, RunAttempt: attempt, URL: url}
}
