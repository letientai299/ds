// Package cli maps command-line input onto ds domain operations.
package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/letientai299/ds/internal/assets"
	"github.com/letientai299/ds/internal/ds"
)

// checkoutRoot is set by the checkout launcher through -ldflags -X.
var checkoutRoot string

// IO is the process boundary of one invocation.
type IO struct {
	Stdin  io.Reader
	Stdout io.Writer
	Stderr io.Writer
	// Environ is os.Environ output.
	Environ []string
	// Interactive reports a terminal on stdin.
	Interactive bool
	// Executable is the running binary path.
	Executable string
	// UID is the effective user ID.
	UID int
	// Runner executes commands; tests substitute fakes.
	Runner ds.Runner
	// Exec replaces the process for the trial shell.
	Exec func(argv0 string, argv, env []string) error
	// Source overrides asset discovery in tests.
	Source assets.Source
	// HTTP overrides the download client in tests.
	HTTP *http.Client
	// SSH overrides the OpenSSH client in tests.
	SSH string
}

// Exit statuses.
const (
	exitOK      = 0
	exitFailed  = 1
	exitInvalid = 2
)

// errUnhealthy makes status --check exit 1 after printing its report.
var errUnhealthy = errors.New("unhealthy")

// childExit propagates the status of a ds that took over an operation.
type childExit struct{ code int }

func (e *childExit) Error() string { return fmt.Sprintf("exit status %d", e.code) }

type app struct {
	io      IO
	home    string
	started bool
}

// Run executes ds with args and returns the exit status.
func Run(ctx context.Context, args []string, sys IO) int {
	a := &app{io: sys}
	root := a.rootCmd()
	root.SetArgs(args)
	root.SetIn(sys.Stdin)
	root.SetOut(sys.Stdout)
	root.SetErr(sys.Stderr)
	err := root.ExecuteContext(ctx)
	switch {
	case err == nil:
		return exitOK
	case errors.Is(err, errUnhealthy):
		return exitFailed
	}
	var child *childExit
	if errors.As(err, &child) {
		return child.code
	}
	var usage *ds.UsageError
	if errors.As(err, &usage) || !a.started {
		fmt.Fprintf(sys.Stderr, "ds: %v\n", err)
		fmt.Fprintln(sys.Stderr, "run 'ds --help' for usage")
		return exitInvalid
	}
	fmt.Fprintf(sys.Stderr, "ds: %v\n", err)
	return exitFailed
}

func (a *app) getenv(key string) string {
	for i := len(a.io.Environ) - 1; i >= 0; i-- {
		if k, v, ok := strings.Cut(a.io.Environ[i], "="); ok && k == key {
			return v
		}
	}
	return ""
}

func (a *app) rootCmd() *cobra.Command {
	var st statusFlags
	root := &cobra.Command{
		Use:   "ds",
		Short: "Configure a development environment on macOS and Ubuntu",
		Long: "ds converges selected layers and components of development tooling\n" +
			"and configuration in a home, locally or over SSH.\n\n" +
			"Run without a command to show status of the saved selection.",
		Args:              noArgs,
		SilenceUsage:      true,
		SilenceErrors:     true,
		PersistentPreRunE: func(*cobra.Command, []string) error { a.started = true; return nil },
		RunE: func(cmd *cobra.Command, _ []string) error {
			return a.status(cmd.Context(), nil, nil, st)
		},
	}
	root.CompletionOptions.DisableDefaultCmd = true
	root.PersistentFlags().StringVar(&a.home, "home", "", "operate on this home instead of $HOME")
	root.SetFlagErrorFunc(func(_ *cobra.Command, err error) error { return &ds.UsageError{Msg: err.Error()} })
	root.AddCommand(
		a.addCmd(), a.statusCmd(), a.shellCmd(), a.deployCmd(),
		a.upgradeCmd(), a.completionCmd(), a.versionCmd(), a.continueCmd(),
	)
	return root
}

func noArgs(cmd *cobra.Command, args []string) error {
	if len(args) > 0 {
		return &ds.UsageError{Msg: fmt.Sprintf("unknown command %q for %q", args[0], cmd.CommandPath())}
	}
	return nil
}

func exactArgs(n int) cobra.PositionalArgs {
	return func(cmd *cobra.Command, args []string) error {
		if len(args) != n {
			return &ds.UsageError{Msg: fmt.Sprintf("%s takes %d argument(s), got %d", cmd.CommandPath(), n, len(args))}
		}
		return nil
	}
}

// env resolves paths, assets, catalog, and platform at the boundary.
func (a *app) env(ctx context.Context, trial bool) (*ds.Env, error) {
	paths, err := ds.ResolvePaths(a.getenv, a.home)
	if err != nil {
		return nil, &ds.UsageError{Msg: err.Error()}
	}
	cfg, err := ds.LoadUserConfig(paths)
	if err != nil {
		return nil, err
	}
	src, err := a.source()
	if err != nil {
		return nil, err
	}
	cat, err := ds.LoadCatalog(src)
	if err != nil {
		return nil, err
	}
	repos, err := cfg.ResolveRepos(cat, src, paths)
	if err != nil {
		return nil, err
	}
	var target ds.Target = ds.HomeTarget{P: paths}
	if trial || (a.home == "" && a.getenv("DS_TRIAL") != "") {
		target = ds.TrialTarget{P: paths}
	}
	runner := a.io.Runner
	if runner == nil {
		runner = ds.ExecRunner{}
	}
	environ := ds.NewEnviron(a.io.Environ)
	client := a.io.HTTP
	if client == nil {
		client = &http.Client{Timeout: 10 * time.Minute}
	}
	url := ds.DefaultDownloadURL
	if cfg.DownloadURL != "" {
		url = cfg.DownloadURL
	}
	if v := a.getenv("DS_DOWNLOAD_URL"); v != "" {
		url = v
	}
	e := &ds.Env{
		Target:      target,
		Source:      src,
		Repos:       repos,
		Catalog:     cat,
		Platform:    ds.DetectPlatform(ctx, runner, environ),
		Runner:      runner,
		Environ:     environ,
		SystemPath:  "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
		Stdin:       a.io.Stdin,
		Stdout:      a.io.Stdout,
		Stderr:      a.io.Stderr,
		Interactive: a.io.Interactive,
		UID:         a.io.UID,
		HTTP:        client,
		DownloadURL: url,
		Mise:        ds.DefaultMise,
		Executable:  a.io.Executable,
	}
	// A separate app keeps flag bindings of this invocation intact.
	var completion bytes.Buffer
	if err := (&app{io: a.io}).rootCmd().GenZshCompletion(&completion); err == nil {
		e.Completion = completion.Bytes()
	}
	return e, nil
}

func (a *app) source() (assets.Source, error) {
	if a.io.Source != nil {
		return a.io.Source, nil
	}
	emb, err := assets.Default()
	if err != nil {
		return nil, err
	}
	if emb != nil {
		return emb, nil
	}
	if checkoutRoot == "" {
		return nil, errors.New("this binary has no assets; run the checkout's ./ds launcher or a main build")
	}
	return assets.Checkout{Root: checkoutRoot}, nil
}

// lock takes the target lock, or adopts one handed over by a parent ds.
func (a *app) lock(e *ds.Env) (*ds.Lock, error) {
	if l, ok := ds.InheritedLock(a.getenv); ok {
		return l, nil
	}
	return ds.AcquireLock(e.Target)
}

type selectorFlags struct{ layers []string }

func (s *selectorFlags) register(cmd *cobra.Command) {
	cmd.Flags().StringArrayVarP(&s.layers, "layer", "l", nil, "select a layer (repeatable)")
}

func (a *app) addCmd() *cobra.Command {
	var sel selectorFlags
	var opt ds.AddOptions
	var dryRun bool
	cmd := &cobra.Command{
		Use:   "add [COMPONENT...] | add -l LAYER [-l LAYER]...",
		Short: "Add components or layers and converge the saved selection",
		Example: "  ds add -l core -l extra\n" +
			"  ds add tmux yazi\n" +
			"  ds add -l ui --dry-run",
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := cmd.Context()
			e, err := a.env(ctx, false)
			if err != nil {
				return err
			}
			req, err := ds.ParseRequest(e.Catalog, sel.layers, args)
			if err != nil {
				return err
			}
			if req == nil {
				return &ds.UsageError{Msg: "add needs components or --layer; for example: ds add -l core"}
			}
			return a.converge(ctx, e, req, opt, dryRun, "add")
		},
		ValidArgsFunction: a.completeComponents,
	}
	sel.register(cmd)
	cmd.Flags().BoolVar(&dryRun, "dry-run", false, "preview without changing anything")
	cmd.Flags().BoolVar(&opt.Force, "force", false, "back up and replace conflicting files")
	cmd.Flags().BoolVar(&opt.NoPackages, "no-packages", false, "skip native packages; require their commands")
	return cmd
}

// converge plans and, unless previewing, executes under the target lock.
func (a *app) converge(ctx context.Context, e *ds.Env, req ds.Request, opt ds.AddOptions, dryRun bool, command string) error {
	if dryRun {
		st, err := ds.LoadState(e.Target)
		if err != nil {
			return err
		}
		p := e.BuildPlan(ctx, st, req, opt)
		ds.RenderPlan(a.io.Stdout, p)
		if len(p.Blockers) > 0 {
			return &ds.BlockedError{Blockers: p.Blockers}
		}
		return nil
	}
	l, err := a.lock(e)
	if err != nil {
		return err
	}
	defer l.Close()
	st, err := ds.LoadState(e.Target)
	if err != nil {
		return err
	}
	p := e.BuildPlan(ctx, st, req, opt)
	if len(p.Blockers) > 0 {
		return &ds.BlockedError{Blockers: p.Blockers}
	}
	if err := e.Execute(ctx, p, &st, command); err != nil {
		return err
	}
	fmt.Fprintf(a.io.Stderr, "ds: converged %s (%d components)\n", p.Selection, len(p.Components))
	return nil
}

type statusFlags struct {
	verbose, json, check bool
}

func (a *app) statusCmd() *cobra.Command {
	var sel selectorFlags
	var st statusFlags
	cmd := &cobra.Command{
		Use:   "status [COMPONENT...] | status -l LAYER [-l LAYER]...",
		Short: "Inspect the saved selection or the given components or layers",
		RunE: func(cmd *cobra.Command, args []string) error {
			return a.status(cmd.Context(), sel.layers, args, st)
		},
		ValidArgsFunction: a.completeComponents,
	}
	sel.register(cmd)
	cmd.Flags().BoolVarP(&st.verbose, "verbose", "v", false, "list healthy items too")
	cmd.Flags().BoolVar(&st.json, "json", false, "print JSON to stdout")
	cmd.Flags().BoolVar(&st.check, "check", false, "exit 1 unless status is complete")
	return cmd
}

func (a *app) status(ctx context.Context, layers, comps []string, flags statusFlags) error {
	e, err := a.env(ctx, false)
	if err != nil {
		return err
	}
	req, err := ds.ParseRequest(e.Catalog, layers, comps)
	if err != nil {
		return err
	}
	st, err := ds.LoadState(e.Target)
	if err != nil {
		return err
	}
	r := e.Status(ctx, st, req)
	if flags.json {
		enc := json.NewEncoder(a.io.Stdout)
		enc.SetIndent("", "  ")
		if err := enc.Encode(r); err != nil {
			return err
		}
	} else {
		ds.RenderStatus(a.io.Stdout, r, flags.verbose)
	}
	if flags.check && !r.Healthy() {
		return errUnhealthy
	}
	return nil
}

func (a *app) shellCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "shell",
		Short: "Enter a persistent trial shell with isolated ds configuration",
		Long: "Enter a Zsh trial whose ds-managed applications use configuration under\n" +
			"<state>/ds/trial. HOME, general XDG paths, Git identity, and SSH\n" +
			"configuration stay real. ds add inside the trial changes the trial\n" +
			"selection; package and tool installations still affect the host.",
		Args: noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			ctx := cmd.Context()
			e, err := a.env(ctx, true)
			if err != nil {
				return err
			}
			home, err := ds.LoadState(ds.HomeTarget{P: e.Target.Paths()})
			if err != nil {
				return err
			}
			l, err := ds.AcquireLock(e.Target)
			if err != nil {
				return err
			}
			env, err := e.PrepareTrial(ctx, home)
			l.Close()
			if err != nil {
				return err
			}
			zsh, err := lookZsh(env)
			if err != nil {
				return err
			}
			if a.io.Exec == nil {
				return errors.New("trial shell needs process replacement")
			}
			return a.io.Exec(zsh, []string{"zsh", "-i"}, env)
		},
	}
}

func lookZsh(env []string) (string, error) {
	path := ""
	for _, kv := range env {
		if v, ok := strings.CutPrefix(kv, "PATH="); ok {
			path = v
		}
	}
	for _, dir := range filepath.SplitList(path + ":/bin:/usr/bin:/opt/homebrew/bin") {
		p := filepath.Join(dir, "zsh")
		if info, err := os.Stat(p); err == nil && !info.IsDir() && info.Mode()&0o111 != 0 {
			return p, nil
		}
	}
	return "", errors.New("zsh is not installed; run ds add zsh first")
}

func (a *app) deployCmd() *cobra.Command {
	var sel selectorFlags
	var home string
	var dryRun, force, noPackages bool
	cmd := &cobra.Command{
		Use:   "deploy HOST [COMPONENT...] | deploy HOST -l LAYER [-l LAYER]...",
		Short: "Install the latest main build on an SSH host and add targets there",
		Long: "Deploy probes HOST through OpenSSH (aliases and ProxyJump work), fetches\n" +
			"and verifies the matching latest main build, transfers it, and runs its\n" +
			"add command remotely. Targets default to the core layer.",
		Example: "  ds deploy my-host -l core -l extra\n" +
			"  ds deploy my-host --home /scratch/job/home -l core",
		Args: func(cmd *cobra.Command, args []string) error {
			if len(args) == 0 {
				return &ds.UsageError{Msg: "deploy needs a HOST"}
			}
			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := cmd.Context()
			host, comps := args[0], args[1:]
			if strings.HasPrefix(host, "-") || host == "" {
				return &ds.UsageError{Msg: fmt.Sprintf("invalid host %q", host)}
			}
			a.home = ""
			e, err := a.env(ctx, false)
			if err != nil {
				return err
			}
			req, err := ds.ParseRequest(e.Catalog, sel.layers, comps)
			if err != nil {
				return err
			}
			if req == nil {
				req = ds.LayerRequest{Layers: []ds.LayerName{"core"}}
			}
			opt := ds.DeployOptions{Host: host, Home: home, AddArgs: remoteSelectors(req), SSH: a.io.SSH}
			for _, f := range []struct {
				name string
				on   bool
			}{{"--dry-run", dryRun}, {"--force", force}, {"--no-packages", noPackages}} {
				if f.on {
					opt.AddArgs = append(opt.AddArgs, f.name)
				}
			}
			return e.Deploy(ctx, opt)
		},
	}
	sel.register(cmd)
	cmd.Flags().StringVar(&home, "home", "", "remote home; relative paths resolve against the login home")
	cmd.Flags().BoolVar(&dryRun, "dry-run", false, "preview remotely; only temporary transport files are written")
	cmd.Flags().BoolVar(&force, "force", false, "back up and replace conflicting remote files")
	cmd.Flags().BoolVar(&noPackages, "no-packages", false, "skip native packages on the remote host")
	return cmd
}

func remoteSelectors(r ds.Request) []string {
	var args []string
	switch r := r.(type) {
	case ds.LayerRequest:
		for _, l := range r.Layers {
			args = append(args, "--layer", string(l))
		}
	case ds.ComponentRequest:
		for _, c := range r.Components {
			args = append(args, string(c))
		}
	}
	return args
}

func (a *app) completionCmd() *cobra.Command {
	return &cobra.Command{
		Use:       "completion zsh|bash",
		Short:     "Generate shell completion",
		Args:      exactArgs(1),
		ValidArgs: []string{"zsh", "bash"},
		RunE: func(cmd *cobra.Command, args []string) error {
			switch args[0] {
			case "zsh":
				return cmd.Root().GenZshCompletion(a.io.Stdout)
			case "bash":
				return cmd.Root().GenBashCompletionV2(a.io.Stdout, true)
			}
			return &ds.UsageError{Msg: fmt.Sprintf("unsupported shell %q (zsh, bash)", args[0])}
		},
	}
}

func (a *app) versionCmd() *cobra.Command {
	var asJSON bool
	cmd := &cobra.Command{
		Use:   "version",
		Short: "Report mode, source or build commit, and asset revisions",
		Args:  noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			e, err := a.env(cmd.Context(), false)
			if err != nil {
				return err
			}
			r := e.Version(cmd.Context())
			if asJSON {
				enc := json.NewEncoder(a.io.Stdout)
				enc.SetIndent("", "  ")
				return enc.Encode(r)
			}
			ds.RenderVersion(a.io.Stdout, r)
			return nil
		},
	}
	cmd.Flags().BoolVar(&asJSON, "json", false, "print JSON to stdout")
	return cmd
}

func (a *app) completeComponents(cmd *cobra.Command, _ []string, _ string) ([]string, cobra.ShellCompDirective) {
	e, err := a.env(cmd.Context(), false)
	if err != nil {
		return nil, cobra.ShellCompDirectiveNoFileComp
	}
	var names []string
	for _, c := range e.Catalog.Components() {
		names = append(names, string(c))
	}
	return names, cobra.ShellCompDirectiveNoFileComp
}
