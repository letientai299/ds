package ds

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/letientai299/ds/internal/assets"
)

// DefaultDownloadURL serves the latest main build through GitHub Pages.
const DefaultDownloadURL = "https://letientai.io/ds"

// Manifest describes the published main build.
type Manifest struct {
	Schema   int                             `json:"schema"`
	Build    string                          `json:"build"`
	Commit   string                          `json:"commit"`
	Sources  map[assets.Repo]assets.Revision `json:"sources"`
	Workflow *assets.Workflow                `json:"workflow,omitempty"`
	Files    map[string]ManifestFile         `json:"files"`
}

// ManifestFile is one platform binary.
type ManifestFile struct {
	Name   string `json:"name"`
	SHA256 string `json:"sha256"`
	Size   int64  `json:"size"`
}

const manifestName = "manifest.json"

// maxFetchAttempts bounds retries across publication races.
const maxFetchAttempts = 3

// retryDelay spaces manifest refetches.
var retryDelay = time.Second

func fetchManifest(ctx context.Context, client *http.Client, base string) (Manifest, error) {
	var m Manifest
	url := strings.TrimRight(base, "/") + "/" + manifestName
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return m, err
	}
	req.Header.Set("Cache-Control", "no-cache")
	resp, err := client.Do(req)
	if err != nil {
		return m, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return m, &httpStatusError{URL: url, Status: resp.StatusCode}
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return m, err
	}
	if err := json.Unmarshal(data, &m); err != nil {
		return m, fmt.Errorf("decode %s: %w", url, err)
	}
	if m.Schema != 1 || m.Build == "" || len(m.Files) == 0 {
		return m, fmt.Errorf("invalid manifest at %s", url)
	}
	return m, nil
}

// FetchBuild downloads and verifies the latest build for platform into
// dest. A missing file or checksum mismatch means the site changed between
// requests, so the manifest is fetched again within a fixed bound.
func FetchBuild(ctx context.Context, client *http.Client, base string, platform Platform, dest string) (Manifest, error) {
	var lastErr error
	for attempt := range maxFetchAttempts {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return Manifest{}, ctx.Err()
			case <-time.After(time.Duration(attempt) * retryDelay):
			}
		}
		m, err := fetchManifest(ctx, client, base)
		if err != nil {
			return Manifest{}, err
		}
		f, ok := m.Files[platform.String()]
		if !ok {
			return m, fmt.Errorf("build %s has no %s binary", m.Build, platform)
		}
		if cachedMatches(dest, f.SHA256) {
			return m, nil
		}
		d := Download{URL: strings.TrimRight(base, "/") + "/" + f.Name, SHA256: f.SHA256}
		err = download(ctx, client, d, dest, 0o755)
		var status *httpStatusError
		var checksum *checksumError
		if errors.As(err, &checksum) || errors.As(err, &status) && status.Status == http.StatusNotFound {
			lastErr = err
			continue
		}
		return m, err
	}
	return Manifest{}, fmt.Errorf("download did not verify after %d attempts: %w", maxFetchAttempts, lastErr)
}

func cachedMatches(p, sha string) bool {
	data, err := os.ReadFile(p)
	return err == nil && digest(data) == sha
}

// LatestManifest reads the published manifest.
func (e *Env) LatestManifest(ctx context.Context) (Manifest, error) {
	return fetchManifest(ctx, e.HTTP, e.DownloadURL)
}

// downloadCache keeps verified binaries for deploys.
func (e *Env) downloadCache(name string) string {
	return filepath.Join(e.Target.Paths().Cache, "ds", "downloads", name)
}
