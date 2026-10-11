package assets

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"strings"
	"testing"
)

func archive(t *testing.T, headers ...*tar.Header) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	for _, h := range headers {
		if err := tw.WriteHeader(h); err != nil {
			t.Fatal(err)
		}
	}
	tw.Close()
	gz.Close()
	return buf.Bytes()
}

func TestExtractRejectsUnsafeEntries(t *testing.T) {
	tests := []struct {
		name string
		h    *tar.Header
	}{
		{"parent traversal", &tar.Header{Name: "ds/../../evil", Typeflag: tar.TypeReg}},
		{"absolute", &tar.Header{Name: "/etc/evil", Typeflag: tar.TypeReg}},
		{"escaping link", &tar.Header{Name: "nvim/x", Typeflag: tar.TypeSymlink, Linkname: "../../.ssh/id"}},
		{"absolute link", &tar.Header{Name: "nvim/x", Typeflag: tar.TypeSymlink, Linkname: "/etc/passwd"}},
	}
	meta := []byte(`{"schema":1,"id":"abc-1","sources":{}}`)
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			emb, err := NewEmbedded(meta, archive(t, tt.h))
			if err != nil {
				t.Fatal(err)
			}
			if err := emb.Extract(t.TempDir()); err == nil || !strings.Contains(err.Error(), "unsafe") {
				t.Fatalf("err = %v", err)
			}
		})
	}
}

func TestNewEmbeddedValidatesID(t *testing.T) {
	for _, meta := range []string{`{"schema":1,"id":"../x"}`, `{"schema":2,"id":"a"}`, `{}`} {
		if _, err := NewEmbedded([]byte(meta), nil); err == nil {
			t.Errorf("%s accepted", meta)
		}
	}
}

func TestParseRef(t *testing.T) {
	for in, ok := range map[string]bool{"ds:dotfiles/x": true, "nvim:": true, "kitty:bin/kt": true, "docker:x": false, "ds": false, "ds:../x": false} {
		if _, err := ParseRef(in); (err == nil) != ok {
			t.Errorf("%s: err = %v", in, err)
		}
	}
}
