package ds

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
)

// site serves manifests and binaries; publish swaps the latest build.
type site struct {
	srv       *httptest.Server
	manifests atomic.Int32
	files     map[string][]byte
	manifest  func(n int32) Manifest
}

func newSite(t *testing.T, manifest func(n int32) Manifest, files map[string][]byte) *site {
	s := &site{files: files, manifest: manifest}
	s.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		name := strings.TrimPrefix(r.URL.Path, "/")
		if name == manifestName {
			if err := json.NewEncoder(w).Encode(s.manifest(s.manifests.Add(1))); err != nil {
				t.Error(err)
			}
			return
		}
		data, ok := s.files[name]
		if !ok {
			http.NotFound(w, r)
			return
		}
		if _, err := w.Write(data); err != nil {
			t.Error(err)
		}
	}))
	t.Cleanup(s.srv.Close)
	return s
}

func sum(b []byte) string {
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

func buildManifest(id string, data []byte) Manifest {
	return Manifest{Schema: 1, Build: id, Commit: "c0ffee", Files: map[string]ManifestFile{
		"linux/amd64": {Name: "ds-" + id + "-linux-amd64", SHA256: sum(data), Size: int64(len(data))},
	}}
}

var linux = Platform{OS: "linux", Arch: "amd64"}

func TestFetchBuild(t *testing.T) {
	t.Parallel()
	v1, v2 := []byte("build one"), []byte("build two")
	tests := []struct {
		name     string
		manifest func(n int32) Manifest
		files    map[string][]byte
		want     string
		err      string
	}{
		{
			name:     "verified",
			manifest: func(int32) Manifest { return buildManifest("b1", v1) },
			files:    map[string][]byte{"ds-b1-linux-amd64": v1},
			want:     "build one",
		},
		{
			name: "binary replaced after manifest",
			manifest: func(n int32) Manifest {
				if n == 1 {
					return buildManifest("b1", v1)
				}
				return buildManifest("b2", v2)
			},
			// b1's name now serves b2's content: a publication race.
			files: map[string][]byte{"ds-b1-linux-amd64": v2, "ds-b2-linux-amd64": v2},
			want:  "build two",
		},
		{
			name: "binary removed after manifest",
			manifest: func(n int32) Manifest {
				if n == 1 {
					return buildManifest("b1", v1)
				}
				return buildManifest("b2", v2)
			},
			files: map[string][]byte{"ds-b2-linux-amd64": v2},
			want:  "build two",
		},
		{
			name:     "persistent mismatch",
			manifest: func(int32) Manifest { return buildManifest("b1", v1) },
			files:    map[string][]byte{"ds-b1-linux-amd64": []byte("tampered")},
			err:      "did not verify after 3 attempts",
		},
		{
			name: "missing platform",
			manifest: func(int32) Manifest {
				m := buildManifest("b1", v1)
				m.Files = map[string]ManifestFile{"darwin/arm64": {}}
				return m
			},
			err: "has no linux/amd64 binary",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s := newSite(t, tt.manifest, tt.files)
			dest := filepath.Join(t.TempDir(), "ds")
			_, err := FetchBuild(context.Background(), s.srv.Client(), s.srv.URL, linux, dest)
			if tt.err != "" {
				if err == nil || !strings.Contains(err.Error(), tt.err) {
					t.Fatalf("err = %v, want %q", err, tt.err)
				}
				if _, statErr := os.Stat(dest); statErr == nil {
					t.Fatal("unverified binary left at destination")
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if got := readFile(t, dest); got != tt.want {
				t.Fatalf("got %q", got)
			}
			if info, _ := os.Stat(dest); info.Mode().Perm() != 0o755 {
				t.Fatalf("mode %v", info.Mode())
			}
		})
	}
}
