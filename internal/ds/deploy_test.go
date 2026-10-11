package ds

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// fakeSSH runs the remote command locally, reporting a Linux host.
const fakeSSH = `#!/bin/sh
printf 'ssh %s\n' "$*" >>"${DS_TEST_LOG:?}"
[ "$1" = -t ] && shift
shift
[ "$1" = -- ] && shift
case "$1" in *'
'*)
	echo 'newline breaks csh login shells' >&2
	exit 2
	;;
esac
if [ "$1" = 'uname -sm' ]; then
	echo 'Linux x86_64'
	exit 0
fi
case "$1" in *'cat >'*) [ -z "${DS_TEST_FAIL_UPLOAD:-}" ] || exec sh -c "$1; exit 9" ;; esac
exec sh -c "$1"
`

// remoteDS records the arguments the deployed binary receives.
const remoteDS = `#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done >"${DS_TEST_ARGS:?}"
`

func deployFixture(t *testing.T) (*fixture, string, string) {
	f := newFixture(t)
	data := []byte(remoteDS)
	s := newSite(t, func(int32) Manifest { return buildManifest("b1", data) }, map[string][]byte{"ds-b1-linux-amd64": data})
	f.env.DownloadURL = s.srv.URL
	f.env.HTTP = s.srv.Client()
	ssh := filepath.Join(f.tools, "ssh")
	writeExec(t, ssh, fakeSSH)
	remoteHome := filepath.Join(t.TempDir(), "remote home")
	remoteCache := filepath.Join(remoteHome, ".cache")
	mustMkdir(t, remoteCache)
	args := filepath.Join(t.TempDir(), "args")
	f.env.Environ = f.env.Environ.with("HOME", remoteHome, "DS_TEST_ARGS", args)
	return f, ssh, remoteCache
}

func TestDeployQuotesArgumentsAndCleansUp(t *testing.T) {
	t.Parallel()
	f, ssh, remoteCache := deployFixture(t)
	home := `/scratch/job one/it's "here"`
	err := f.env.Deploy(context.Background(), DeployOptions{
		Host: "lease-1", Home: home, SSH: ssh,
		AddArgs: []string{"--layer", "core", "--layer", "extra", "--dry-run"},
	})
	if err != nil {
		t.Fatalf("%v\n%s", err, f.err.String())
	}
	want := []string{"--home", home, "add", "--layer", "core", "--layer", "extra", "--dry-run"}
	got := strings.Split(strings.TrimSuffix(readFile(t, f.env.Environ.get("DS_TEST_ARGS")), "\n"), "\n")
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Fatalf("remote args = %q", got)
	}
	if entries, _ := os.ReadDir(remoteCache); len(entries) != 0 {
		t.Fatalf("remote temporary files remain: %v", entries)
	}
	if !strings.Contains(f.err.String(), "build b1 (commit c0ffee) to lease-1 (linux/amd64)") {
		t.Fatalf("output:\n%s", f.err.String())
	}
}

func TestDeployFailedTransferLeavesNothing(t *testing.T) {
	t.Parallel()
	f, ssh, remoteCache := deployFixture(t)
	f.env.Environ = f.env.Environ.with("DS_TEST_FAIL_UPLOAD", "1")
	err := f.env.Deploy(context.Background(), DeployOptions{Host: "lease-1", SSH: ssh, AddArgs: []string{"--layer", "core"}})
	if err == nil || !strings.Contains(err.Error(), "transfer to lease-1") {
		t.Fatalf("err = %v", err)
	}
	if entries, _ := os.ReadDir(remoteCache); len(entries) != 0 {
		t.Fatalf("remote temporary files remain: %v", entries)
	}
	if _, statErr := os.Stat(f.env.Environ.get("DS_TEST_ARGS")); statErr == nil {
		t.Fatal("remote ds ran after a failed transfer")
	}
}
