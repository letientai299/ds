package ds

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
)

// Platform describes the host ds configures.
type Platform struct {
	OS   string // darwin or linux
	Arch string // arm64 or amd64
	// Libc is glibc or musl on Linux and empty on macOS.
	Libc string
	// Glibc is the glibc version when Libc is glibc.
	Glibc string
}

func (p Platform) String() string { return p.OS + "/" + p.Arch }

// MiseKey is mise's platform key, such as macos-arm64 or linux-x64.
func (p Platform) MiseKey() string {
	os := p.OS
	if os == "darwin" {
		os = "macos"
	}
	arch := p.Arch
	if arch == "amd64" {
		arch = "x64"
	}
	return os + "-" + arch
}

// ParsePlatform parses uname output such as "Linux x86_64".
func ParsePlatform(uname string) (Platform, error) {
	fields := strings.Fields(uname)
	if len(fields) != 2 {
		return Platform{}, fmt.Errorf("unexpected uname output %q", uname)
	}
	var p Platform
	switch fields[0] {
	case "Darwin":
		p.OS = "darwin"
	case "Linux":
		p.OS = "linux"
	default:
		return Platform{}, fmt.Errorf("unsupported operating system %s", fields[0])
	}
	switch fields[1] {
	case "arm64", "aarch64":
		p.Arch = "arm64"
	case "x86_64", "amd64":
		p.Arch = "amd64"
	default:
		return Platform{}, fmt.Errorf("unsupported architecture %s", fields[1])
	}
	return p, nil
}

// DetectPlatform inspects the running host.
func DetectPlatform(ctx context.Context, r Runner, env envList) Platform {
	p := Platform{OS: runtime.GOOS, Arch: runtime.GOARCH}
	if p.OS != "linux" {
		return p
	}
	if musl, _ := filepath.Glob("/lib/ld-musl-*.so.1"); len(musl) > 0 {
		p.Libc = "musl"
		return p
	}
	if _, err := os.Stat("/etc/alpine-release"); err == nil {
		p.Libc = "musl"
		return p
	}
	p.Libc = "glibc"
	if out, err := output(ctx, r, Cmd{Args: []string{"getconf", "GNU_LIBC_VERSION"}, Env: env}); err == nil {
		if f := strings.Fields(out); len(f) == 2 {
			p.Glibc = f[1]
		}
	}
	return p
}

// versionAtLeast compares dotted numeric versions.
func versionAtLeast(have, want string) bool {
	h := strings.Split(have, ".")
	w := strings.Split(want, ".")
	for i := range max(len(h), len(w)) {
		var hv, wv int
		if i < len(h) {
			hv, _ = strconv.Atoi(h[i])
		}
		if i < len(w) {
			wv, _ = strconv.Atoi(w[i])
		}
		if hv != wv {
			return hv > wv
		}
	}
	return true
}

// platformBlocker rejects hosts ds does not support, or returns "".
func platformBlocker(p Platform) string {
	if p.Libc == "musl" {
		return "musl Linux (Alpine) is unsupported"
	}
	return ""
}

// glibcBlocker explains why a component cannot run on p, or returns "".
func glibcBlocker(p Platform, comp *Component) string {
	if comp.Glibc == "" || p.OS != "linux" {
		return ""
	}
	if p.Glibc == "" || !versionAtLeast(p.Glibc, comp.Glibc) {
		return fmt.Sprintf("%s requires glibc %s+ (found %q)", comp.Name, comp.Glibc, p.Glibc)
	}
	return ""
}
