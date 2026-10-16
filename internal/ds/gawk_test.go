package ds

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestGawkPostinstall(t *testing.T) {
	t.Parallel()
	for _, phase := range []string{"configure", "build", "install", "success"} {
		t.Run(phase, func(t *testing.T) {
			t.Parallel()
			dir := t.TempDir()
			prefix := filepath.Join(dir, "install with spaces")
			tools := filepath.Join(dir, "tools")
			writeExec(t, filepath.Join(prefix, "configure"), `#!/bin/sh
[ "$PHASE" != configure ] || exit 23
`)
			writeExec(t, filepath.Join(tools, "make"), `#!/bin/sh
if [ "$1" = install ]; then
    mkdir -p "$MISE_TOOL_INSTALL_PATH/bin"
    [ "$PHASE" != install ] || exit 23
    printf '#!/bin/sh\nexit 0\n' > "$MISE_TOOL_INSTALL_PATH/bin/gawk"
else
    [ "$PHASE" != build ] || exit 23
fi
`)
			cmd := exec.Command("sh", filepath.Join(repoRoot(t), "assets/tools/gawk-postinstall"))
			cmd.Env = append(os.Environ(), "MISE_TOOL_INSTALL_PATH="+prefix, "PHASE="+phase, "PATH="+tools+string(os.PathListSeparator)+os.Getenv("PATH"))
			output, err := cmd.CombinedOutput()
			if phase == "success" {
				if err != nil {
					t.Fatalf("postinstall: %v\n%s", err, output)
				}
				if target, err := os.Readlink(filepath.Join(prefix, "bin/awk")); err != nil || target != "gawk" {
					t.Fatalf("awk link: %q %v", target, err)
				}
			} else {
				if exit, ok := err.(*exec.ExitError); !ok || exit.ExitCode() != 23 {
					t.Fatalf("failure status: %v\n%s", err, output)
				}
				if _, err := os.Stat(prefix); !os.IsNotExist(err) {
					t.Fatalf("partial installation remains: %v", err)
				}
			}
			if builds, _ := filepath.Glob(prefix + ".build.*"); len(builds) != 0 {
				t.Fatalf("build directories remain: %v", builds)
			}
		})
	}
}
