package ds

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"time"

	"github.com/letientai299/ds/internal/assets"
)

// BlockedError reports a plan that cannot execute.
type BlockedError struct{ Blockers []Blocker }

func (e *BlockedError) Error() string {
	lines := make([]string, len(e.Blockers))
	for i, b := range e.Blockers {
		lines[i] = "  " + b.String()
	}
	return "blocked:\n" + strings.Join(lines, "\n")
}

// PartialError reports a failed action after earlier actions completed.
type PartialError struct {
	Failed    string
	Completed []string
	Record    string
	Err       error
}

func (e *PartialError) Error() string {
	return fmt.Sprintf("%s failed: %v\n%d actions completed first; record: %s\nrerun to converge from the current state",
		e.Failed, e.Err, len(e.Completed), e.Record)
}

func (e *PartialError) Unwrap() error { return e.Err }

// operation is the progress record of one mutation.
type operation struct {
	Command   string    `json:"command"`
	Started   time.Time `json:"started"`
	Finished  time.Time `json:"finished,omitzero"`
	Selection Selection `json:"selection"`
	Completed []string  `json:"completed"`
	Failed    string    `json:"failed,omitempty"`
	Error     string    `json:"error,omitempty"`
}

// Execute applies a plan, recording progress and ownership as it goes.
func (e *Env) Execute(ctx context.Context, p *Plan, st *State, command string) error {
	if len(p.Blockers) > 0 {
		return &BlockedError{Blockers: p.Blockers}
	}
	op := operation{Command: command, Started: e.now().UTC(), Selection: p.Selection, Completed: []string{}}
	record := filepath.Join(e.Target.StateDir(), "operations",
		op.Started.Format("20060102T150405.000Z")+"-"+command+".json")
	save := func() {
		data, _ := json.MarshalIndent(op, "", "  ")
		if err := writeAtomic(record, append(data, '\n'), 0o644); err != nil {
			e.printf("ds: record operation: %v\n", err)
		}
	}
	for _, a := range p.Actions {
		if err := ctx.Err(); err != nil {
			return err
		}
		e.printf("ds: %s\n", a.Describe())
		if err := e.apply(ctx, a, st); err != nil {
			op.Failed, op.Error = a.Describe(), err.Error()
			save()
			return &PartialError{Failed: a.Describe(), Completed: op.Completed, Record: record, Err: err}
		}
		op.Completed = append(op.Completed, a.Describe())
	}
	st.Selection = p.Selection
	if err := SaveState(e.Target, *st); err != nil {
		return err
	}
	op.Finished = e.now().UTC()
	save()
	return nil
}

func (e *Env) apply(ctx context.Context, a Action, st *State) error {
	switch a := a.(type) {
	case StageBuild:
		emb, ok := e.Source.(*assets.Embedded)
		if !ok {
			return errors.New("staging requires a main build")
		}
		return stageBuild(emb, e.Executable, a.Dir)
	case FetchMise:
		return download(ctx, e.HTTP, a.Download, a.Path, 0o755)
	case InstallPackages:
		return e.installPackages(ctx, a)
	case CloneRepo:
		return e.cloneRepo(ctx, a)
	case BuildHelper:
		// Naming go limits mise to the pinned Go, not every repository tool.
		c := Cmd{
			Args: []string{a.Mise, "-C", a.Dir, "exec", "go", "--", "go", "build", "-trimpath", "-o", a.Output, a.Package},
			Env:  e.Environ.with("CGO_ENABLED", "0", "MISE_TRUSTED_CONFIG_PATHS", a.Dir, "MISE_YES", "1"),
			Dir:  a.Dir, Stdout: e.Stderr, Stderr: e.Stderr,
		}
		return e.Runner.Run(ctx, c)
	case FileChange:
		return e.applyFile(a, st)
	case InstallTools:
		return e.Runner.Run(ctx, e.miseCmd(a.Mise, append([]string{"install"}, a.Tools...)...))
	case BootstrapNeovim:
		return e.bootstrapNeovim(ctx, a)
	case ActivateBuild:
		return activateBuild(e.Target.Paths().DSData(), a.ID)
	}
	return fmt.Errorf("unknown action %T", a)
}

func (e *Env) applyFile(a FileChange, st *State) error {
	target := a.Entry.path()
	if in := a.Entry.inspect(st.Owned, e.legacyRoots()); in.State != a.Expect {
		return fmt.Errorf("%s changed since planning (now %s); rerun", target, in.State)
	}
	inPlace := editsInPlace(a.Entry)
	if a.Backup != "" {
		backup := moveToBackup
		if inPlace {
			backup = copyToBackup
		}
		if err := backup(target, a.Backup); err != nil {
			return err
		}
	}
	replace := a.Expect == stateStale || (inPlace && a.Expect == stateConflict)
	own, err := a.Entry.write(replace)
	if err != nil {
		return err
	}
	st.Owned[target] = own
	return SaveState(e.Target, *st)
}

func (e *Env) installPackages(ctx context.Context, a InstallPackages) error {
	if a.Sudo && e.Interactive {
		c := Cmd{Args: []string{"sudo", "-v"}, Env: e.Environ, Stdin: e.Stdin, Stdout: e.Stderr, Stderr: e.Stderr}
		if err := e.Runner.Run(ctx, c); err != nil {
			return fmt.Errorf("sudo authorization: %w", err)
		}
	}
	args := []string{"bootstrap", "packages", "apply", "--yes"}
	if a.Manager == "apt" {
		args = append(args, "--update")
	}
	for _, pkg := range a.Packages {
		args = append(args, a.Manager+":"+pkg)
	}
	c := e.miseCmd(a.Mise, args...)
	c.Env = c.Env.with("DEBIAN_FRONTEND", "noninteractive", "NONINTERACTIVE", "1", "HOMEBREW_NO_ASK", "1")
	if e.Interactive {
		c.Stdin = e.Stdin
	}
	return e.Runner.Run(ctx, c)
}

const neovimBootstrap = "+lua local ok, err = pcall(function() require('lib.bootstrap').run() end); " +
	"if not ok then print(err); vim.cmd('cquit 1') end"

func (e *Env) bootstrapNeovim(ctx context.Context, a BootstrapNeovim) error {
	env := e.miseEnv().with("NVIM_APPNAME", a.AppName, "GIT_TERMINAL_PROMPT", "0")
	nvim := lookPath("nvim", env.get("PATH"))
	if nvim == "" {
		return errors.New("nvim is not on PATH after installation")
	}
	return e.Runner.Run(ctx, Cmd{
		Args: []string{nvim, "--headless", neovimBootstrap, "+qa!"},
		Env:  env, Dir: e.Target.Paths().Home,
		Stdout: e.Stderr, Stderr: e.Stderr, Timeout: 10 * time.Minute,
	})
}
