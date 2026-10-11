package ds

import (
	"bytes"
	"context"
	"path/filepath"
	"testing"
)

func TestRunnerUsesCommandPath(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	writeExec(t, filepath.Join(dir, "ds-probe"), "#!/bin/sh\necho found\n")
	var out bytes.Buffer
	c := Cmd{Args: []string{"ds-probe"}, Env: envList{"PATH=" + dir + ":/usr/bin:/bin"}, Stdout: &out}
	if err := (ExecRunner{}).Run(context.Background(), c); err != nil || out.String() != "found\n" {
		t.Fatalf("err = %v, out = %q", err, out.String())
	}
}
