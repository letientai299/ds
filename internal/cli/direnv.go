package cli

import (
	"os"

	"github.com/spf13/cobra"

	"github.com/letientai299/ds/internal/ds"
)

func (a *app) direnvCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "direnv",
		Short: "Open or initialize the project's local mise config",
		Args:  noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			dir, err := os.Getwd()
			if err != nil {
				return err
			}
			runner := a.io.Runner
			if runner == nil {
				runner = ds.ExecRunner{}
			}
			path, err := ds.PrepareDirenv(cmd.Context(), runner, a.io.Environ, dir)
			if err != nil {
				return err
			}
			editor := a.getenv("VISUAL")
			if editor == "" {
				editor = a.getenv("EDITOR")
			}
			if editor == "" {
				editor = "vi"
			}
			return runner.Run(cmd.Context(), ds.Cmd{
				Args:   []string{"sh", "-c", `exec ` + editor + ` "$@"`, "ds-direnv", path},
				Env:    ds.NewEnviron(a.io.Environ),
				Dir:    dir,
				Stdin:  a.io.Stdin,
				Stdout: a.io.Stdout,
				Stderr: a.io.Stderr,
			})
		},
	}
}
