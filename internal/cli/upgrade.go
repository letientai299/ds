package cli

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"slices"
	"strings"

	"github.com/spf13/cobra"

	"github.com/letientai299/ds/internal/assets"
	"github.com/letientai299/ds/internal/ds"
)

func (a *app) upgradeCmd() *cobra.Command {
	var skip []string
	var dryRun bool
	cmd := &cobra.Command{
		Use:   "upgrade [ds|tools|plugins|system|all]...",
		Short: "Upgrade ds, selected tools, Neovim plugins, and system packages",
		Long: "Bare upgrade covers every category. The ds category runs first: it\n" +
			"fast-forwards clean user checkouts and resets ds-managed clones; a\n" +
			"checkout then rebuilds, and a main build fetches and verifies the latest\n" +
			"build. The resulting ds converges the saved selection and upgrades the\n" +
			"remaining categories.",
		Example:           "  ds upgrade\n  ds upgrade tools\n  ds upgrade --skip system",
		ValidArgsFunction: completeUpgrade,
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := cmd.Context()
			cats, err := ds.ParseCategories(args, skip)
			if err != nil {
				return err
			}
			e, err := a.env(ctx, false)
			if err != nil {
				return err
			}
			var lock *ds.Lock
			if !dryRun {
				if lock, err = a.lock(e); err != nil {
					return err
				}
				defer lock.Close()
			}
			st, err := ds.LoadState(e.Target)
			if err != nil {
				return err
			}
			if !slices.Contains(cats, ds.CatDS) {
				return e.RunCategories(ctx, st, cats, dryRun)
			}
			rest := slices.DeleteFunc(slices.Clone(cats), func(c ds.Category) bool { return c == ds.CatDS })
			if err := e.SyncSources(ctx, dryRun); err != nil {
				return err
			}
			next := ""
			switch src := e.Source.(type) {
			case assets.Checkout:
				next = src.Launcher()
			case *assets.Embedded:
				if next, _, err = e.FetchCandidate(ctx, dryRun); err != nil {
					return err
				}
			}
			if dryRun || next == "" {
				return a.continueUpgrade(ctx, e, st, rest, dryRun)
			}
			return a.handoff(ctx, next, lock, rest)
		},
	}
	cmd.Long += "\n\n" + formatChoices("Categories", upgradeChoices())
	cmd.Flags().StringArrayVar(&skip, "skip", nil, "skip a category, such as system (repeatable)")
	registerCompletion(cmd, "skip", completeSkip)
	cmd.Flags().BoolVar(&dryRun, "dry-run", false, "preview without changing anything")
	return cmd
}

// handoff runs the upgraded ds with the held lock so it converges and
// finishes the remaining categories.
func (a *app) handoff(ctx context.Context, exe string, lock *ds.Lock, rest []ds.Category) error {
	args := []string{"__continue", "--categories", ds.FormatCategories(rest)}
	if a.home != "" {
		args = append(args, "--home", a.home)
	}
	cmd := exec.CommandContext(ctx, exe, args...)
	cmd.Env = append(slices.Clone(a.io.Environ), ds.LockFDEnv+"=3")
	cmd.ExtraFiles = []*os.File{lock.File()}
	cmd.Stdin, cmd.Stdout, cmd.Stderr = a.io.Stdin, a.io.Stdout, a.io.Stderr
	err := cmd.Run()
	var exit *exec.ExitError
	if errors.As(err, &exit) {
		return &childExit{code: exit.ExitCode()}
	}
	return err
}

// continueCmd is the upgraded ds's entrypoint after a handoff.
func (a *app) continueCmd() *cobra.Command {
	var categories string
	cmd := &cobra.Command{
		Use:    "__continue",
		Hidden: true,
		Args:   noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			ctx := cmd.Context()
			var cats []ds.Category
			if categories != "" {
				var err error
				if cats, err = ds.ParseCategories(strings.Split(categories, ","), nil); err != nil {
					return err
				}
			}
			e, err := a.env(ctx, false)
			if err != nil {
				return err
			}
			lock, err := a.lock(e)
			if err != nil {
				return err
			}
			defer lock.Close()
			st, err := ds.LoadState(e.Target)
			if err != nil {
				return err
			}
			if err := a.continueUpgrade(ctx, e, st, cats, false); err != nil {
				return err
			}
			e.ClearCandidates()
			return nil
		},
	}
	cmd.Flags().StringVar(&categories, "categories", "", "categories left after ds")
	return cmd
}

// continueUpgrade converges the saved selection, then runs categories.
func (a *app) continueUpgrade(ctx context.Context, e *ds.Env, st ds.State, cats []ds.Category, dryRun bool) error {
	p := e.BuildPlan(ctx, st, nil, ds.AddOptions{})
	if dryRun {
		ds.RenderPlan(a.io.Stdout, p)
	} else if err := e.Execute(ctx, p, &st, "upgrade"); err != nil {
		return err
	}
	if len(cats) == 0 {
		return nil
	}
	return e.RunCategories(ctx, st, cats, dryRun)
}
