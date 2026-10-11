package ds

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

// DeployOptions configure an SSH deployment.
type DeployOptions struct {
	Host string
	// Home is a remote path; relative paths resolve on the remote host.
	Home string
	// AddArgs are the remote `ds add` selectors and flags.
	AddArgs []string
	// SSH is the OpenSSH client; tests substitute a fake.
	SSH string
}

// Deploy fetches the latest main build for the remote platform, transfers
// it, and runs its add command remotely. The transferred binary lives in a
// remote temporary directory that is removed on exit.
func (e *Env) Deploy(ctx context.Context, opt DeployOptions) error {
	ssh := opt.SSH
	if ssh == "" {
		ssh = "ssh"
	}
	run := func(c Cmd) error {
		c.Args = append([]string{ssh}, c.Args...)
		c.Env = e.Environ
		return e.Runner.Run(ctx, c)
	}
	remote := func(args ...string) string {
		quoted := make([]string, len(args))
		for i, a := range args {
			quoted[i] = shellQuote(a)
		}
		return strings.Join(quoted, " ")
	}

	var uname bytes.Buffer
	if err := run(Cmd{Args: []string{opt.Host, "--", "uname -sm"}, Stdout: &uname, Stderr: e.Stderr, Timeout: inspectTimeout}); err != nil {
		return fmt.Errorf("probe %s: %w", opt.Host, err)
	}
	platform, err := ParsePlatform(strings.TrimSpace(uname.String()))
	if err != nil {
		return fmt.Errorf("probe %s: %w", opt.Host, err)
	}
	bin := e.downloadCache("deploy-" + platform.OS + "-" + platform.Arch)
	m, err := FetchBuild(ctx, e.HTTP, e.DownloadURL, platform, bin)
	if err != nil {
		return err
	}
	e.printf("ds deploy: build %s (commit %s) to %s (%s)\n", m.Build, short(m.Commit), opt.Host, platform)

	data, err := os.ReadFile(bin)
	if err != nil {
		return err
	}
	// The cache directory avoids /tmp, which hardened hosts mount noexec.
	upload := oneLine(`umask 077
cache=${XDG_CACHE_HOME:-$HOME/.cache}
mkdir -p "$cache" || exit 1
d=$(mktemp -d "$cache/ds-deploy.XXXXXX") || exit 1
trap 'rm -rf "$d"' EXIT
cat >"$d/ds" || exit 1
chmod 700 "$d/ds" || exit 1
size=$(wc -c <"$d/ds") || exit 1
trap - EXIT
printf '%s\n%s\n' $size "$d"`)
	var out bytes.Buffer
	err = run(Cmd{Args: []string{opt.Host, "--", remote("sh", "-c", upload)}, Stdin: bytes.NewReader(data), Stdout: &out, Stderr: e.Stderr})
	sizeLine, dir, _ := strings.Cut(strings.TrimSuffix(out.String(), "\n"), "\n")
	if !strings.HasPrefix(dir, "/") || !strings.Contains(dir, "/ds-deploy.") || strings.Contains(dir, "\n") {
		dir = ""
	}
	cleanup := func() {
		if dir == "" {
			return
		}
		if err := run(Cmd{Args: []string{opt.Host, "--", remote("rm", "-rf", "--", dir)}, Stderr: e.Stderr}); err != nil {
			e.printf("ds deploy: remove %s on %s: %v\n", dir, opt.Host, err)
		}
	}
	switch size, _ := strconv.Atoi(strings.TrimSpace(sizeLine)); {
	case err != nil:
		cleanup()
		return fmt.Errorf("transfer to %s: %w", opt.Host, err)
	case dir == "":
		return fmt.Errorf("transfer to %s: unexpected reply %q", opt.Host, out.String())
	case size != len(data):
		cleanup()
		return fmt.Errorf("transfer to %s: received %d of %d bytes", opt.Host, size, len(data))
	}

	invoke := oneLine(`d=$1
shift
trap 'rm -rf "$d"' EXIT
"$d/ds" "$@"`)
	args := []string{"sh", "-c", invoke, "ds-deploy", dir}
	if opt.Home != "" {
		args = append(args, "--home", opt.Home)
	}
	args = append(append(args, "add"), opt.AddArgs...)
	sshArgs := []string{opt.Host, "--", remote(args...)}
	if e.Interactive {
		sshArgs = append([]string{"-t"}, sshArgs...)
	}
	err = run(Cmd{Args: sshArgs, Stdin: e.Stdin, Stdout: e.Stdout, Stderr: e.Stderr})
	var exit *exec.ExitError
	if errors.As(err, &exit) && exit.ExitCode() == 255 {
		// ssh failed before the remote trap could clean up.
		cleanup()
	}
	if err != nil {
		return fmt.Errorf("remote ds add on %s: %w", opt.Host, err)
	}
	return nil
}

// oneLine joins script lines because csh login shells reject newlines inside
// quotes.
func oneLine(script string) string {
	return strings.ReplaceAll(script, "\n", "; ")
}
