package ds

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// Cmd is an external command with an argument array.
type Cmd struct {
	Args    []string
	Env     envList
	Dir     string
	Stdin   io.Reader
	Stdout  io.Writer
	Stderr  io.Writer
	Timeout time.Duration
	// ExtraFiles become descriptors 3 and up in the child.
	ExtraFiles []*os.File
}

// Runner executes commands.
type Runner interface {
	Run(ctx context.Context, c Cmd) error
}

// ExecRunner runs real processes.
type ExecRunner struct{}

// inspectTimeout bounds read-only probes.
const inspectTimeout = 20 * time.Second

func (ExecRunner) Run(ctx context.Context, c Cmd) error {
	if len(c.Args) == 0 || c.Args[0] == "" {
		return errors.New("empty command")
	}
	if c.Timeout > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, c.Timeout)
		defer cancel()
	}
	name := c.Args[0]
	// os/exec searches the ds process PATH, not the command's.
	if c.Env != nil {
		if p := lookPath(name, c.Env.get("PATH")); p != "" {
			name = p
		}
	}
	cmd := exec.CommandContext(ctx, name, c.Args[1:]...)
	cmd.Env = c.Env
	cmd.Dir = c.Dir
	cmd.Stdin = c.Stdin
	cmd.Stdout = c.Stdout
	cmd.Stderr = c.Stderr
	cmd.ExtraFiles = c.ExtraFiles
	cmd.Cancel = func() error { return cmd.Process.Signal(syscall.SIGTERM) }
	cmd.WaitDelay = 5 * time.Second
	err := cmd.Run()
	if ctx.Err() != nil && errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return fmt.Errorf("%s timed out", filepath.Base(c.Args[0]))
	}
	return err
}

// output runs a command and returns trimmed stdout.
func output(ctx context.Context, r Runner, c Cmd) (string, error) {
	var stdout, stderr bytes.Buffer
	c.Stdout = &stdout
	c.Stderr = &stderr
	if c.Timeout == 0 {
		c.Timeout = inspectTimeout
	}
	if err := r.Run(ctx, c); err != nil {
		if msg := strings.TrimSpace(stderr.String()); msg != "" {
			return stdout.String(), fmt.Errorf("%s: %w: %s", filepath.Base(c.Args[0]), err, lastLine(msg))
		}
		return stdout.String(), fmt.Errorf("%s: %w", filepath.Base(c.Args[0]), err)
	}
	return strings.TrimSpace(stdout.String()), nil
}

func lastLine(s string) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	return lines[len(lines)-1]
}

// lookPath finds an executable in a PATH list without consulting the
// process environment.
func lookPath(name, pathList string) string {
	if strings.Contains(name, "/") {
		if isExecutable(name) {
			return name
		}
		return ""
	}
	for _, dir := range filepath.SplitList(pathList) {
		if dir == "" || !filepath.IsAbs(dir) {
			continue
		}
		p := filepath.Join(dir, name)
		if isExecutable(p) {
			return p
		}
	}
	return ""
}

func isExecutable(p string) bool {
	info, err := os.Stat(p)
	return err == nil && info.Mode().IsRegular() && info.Mode().Perm()&0o111 != 0
}

// envList is an ordered environment with override semantics.
type envList []string

func (e envList) get(key string) string {
	for i := len(e) - 1; i >= 0; i-- {
		if k, v, ok := strings.Cut(e[i], "="); ok && k == key {
			return v
		}
	}
	return ""
}

// with returns a copy with key set, or removed when value is empty.
func (e envList) with(pairs ...string) envList {
	out := make(envList, 0, len(e)+len(pairs)/2)
	drop := map[string]bool{}
	for i := 0; i+1 < len(pairs); i += 2 {
		drop[pairs[i]] = true
	}
	for _, kv := range e {
		k, _, _ := strings.Cut(kv, "=")
		if !drop[k] {
			out = append(out, kv)
		}
	}
	for i := 0; i+1 < len(pairs); i += 2 {
		if pairs[i+1] != "" {
			out = append(out, pairs[i]+"="+pairs[i+1])
		}
	}
	return out
}
