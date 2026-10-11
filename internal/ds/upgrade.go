package ds

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/letientai299/ds/internal/assets"
)

// Category is an upgrade scope.
type Category string

// Upgrade categories in execution order.
const (
	CatDS      Category = "ds"
	CatTools   Category = "tools"
	CatPlugins Category = "plugins"
	CatSystem  Category = "system"
)

// Categories lists every category in execution order.
var Categories = []Category{CatDS, CatTools, CatPlugins, CatSystem}

// ParseCategories validates requested and skipped categories.
func ParseCategories(args, skip []string) ([]Category, error) {
	valid := func(s string) bool { return s == "all" || slices.Contains(Categories, Category(s)) }
	want := map[Category]bool{}
	for _, a := range args {
		if !valid(a) {
			return nil, usagef("unknown upgrade category %q (ds, tools, plugins, system, all)", a)
		}
		if a == "all" {
			for _, c := range Categories {
				want[c] = true
			}
			continue
		}
		want[Category(a)] = true
	}
	explicit := len(args) > 0 && !slices.Contains(args, "all")
	if len(args) == 0 {
		for _, c := range Categories {
			want[c] = true
		}
	}
	for _, s := range skip {
		if s == "all" || !valid(s) {
			return nil, usagef("unknown skip category %q (ds, tools, plugins, system)", s)
		}
		if explicit && want[Category(s)] {
			return nil, usagef("cannot both upgrade and skip %s", s)
		}
		delete(want, Category(s))
	}
	out := slices.DeleteFunc(slices.Clone(Categories), func(c Category) bool { return !want[c] })
	if len(out) == 0 {
		return nil, usagef("nothing to upgrade")
	}
	return out, nil
}

// FormatCategories joins categories for a continuation command.
func FormatCategories(cats []Category) string { return joinNames(cats, ",") }

// StageError reports failed upgrade categories after completed ones.
type StageError struct {
	Completed []Category
	Failed    map[Category]error
}

func (e *StageError) Error() string {
	var parts []string
	for _, c := range Categories {
		if err, ok := e.Failed[c]; ok {
			parts = append(parts, fmt.Sprintf("%s: %v", c, err))
		}
	}
	msg := "upgrade failed: " + strings.Join(parts, "; ")
	if len(e.Completed) > 0 {
		msg += "\ncompleted: " + FormatCategories(e.Completed)
	}
	return msg
}

// RunCategories upgrades tools, plugins, and system packages. The ds
// category is handled by the caller before this runs.
func (e *Env) RunCategories(ctx context.Context, st State, cats []Category, dryRun bool) error {
	comps := e.Catalog.Expand(st.Selection)
	failed := map[Category]error{}
	var completed []Category
	for _, c := range cats {
		var err error
		switch c {
		case CatDS:
			continue
		case CatTools:
			err = e.upgradeTools(ctx, comps, dryRun)
		case CatPlugins:
			err = e.upgradePlugins(ctx, comps, dryRun)
		case CatSystem:
			err = e.upgradeSystem(ctx, dryRun)
		}
		if err != nil {
			e.printf("ds upgrade: %s failed: %v\n", c, err)
			failed[c] = err
			continue
		}
		completed = append(completed, c)
	}
	if len(failed) > 0 {
		return &StageError{Completed: completed, Failed: failed}
	}
	return nil
}

func (e *Env) upgradeTools(ctx context.Context, comps []ComponentName, dryRun bool) error {
	tools := toolNames(e.Catalog, comps)
	if len(tools) == 0 {
		e.printf("ds upgrade: tools skipped; none selected\n")
		return nil
	}
	mise, _ := e.findMise(ctx)
	if mise.Path == "" {
		return errors.New("mise is missing; run ds add first")
	}
	if dryRun {
		e.printf("ds upgrade: would run mise upgrade %s\n", strings.Join(tools, " "))
		return nil
	}
	e.printf("ds upgrade: tools\n")
	return e.Runner.Run(ctx, e.miseCmd(mise.Path, append([]string{"upgrade"}, tools...)...))
}

// neovimUpdate updates lazy.nvim plugins and fails on task errors.
const neovimUpdate = "+lua local ok, err = pcall(function() " +
	"local loaded, lazy = pcall(require, 'lazy'); " +
	"if not loaded then print('lazy.nvim is not installed'); return end; " +
	"local config = require('lazy.core.config'); " +
	"config.options.headless = {process=false, log=false, task=false, colors=false}; " +
	"lazy.update({wait=true, show=false}); " +
	"local failed = false; " +
	"local names = vim.tbl_keys(config.plugins); table.sort(names); " +
	"for _, name in ipairs(names) do local plugin = config.plugins[name]; " +
	"local updated = plugin._.updated; " +
	"if updated and updated.from ~= updated.to then " +
	"print('[' .. name .. '] updated ' .. updated.from:sub(1, 7) .. ' -> ' .. updated.to:sub(1, 7)) end; " +
	"for _, task in ipairs(plugin._.tasks or {}) do " +
	"if task:has_errors() then failed = true; " +
	"print('[' .. name .. '] ' .. task.name .. ': ' .. task:output(vim.log.levels.ERROR)) end " +
	"end end; if failed then error('Neovim plugin upgrade failed') end " +
	"end); if not ok then print(err); vim.cmd('cquit 1') end"

func (e *Env) upgradePlugins(ctx context.Context, comps []ComponentName, dryRun bool) error {
	if !slices.Contains(comps, "neovim") {
		e.printf("ds upgrade: plugins skipped; neovim not selected\n")
		return nil
	}
	env := e.miseEnv().with("NVIM_APPNAME", e.Target.NvimAppName(), "GIT_TERMINAL_PROMPT", "0")
	nvim := lookPath("nvim", env.get("PATH"))
	if nvim == "" {
		return errors.New("nvim is not installed")
	}
	if dryRun {
		e.printf("ds upgrade: would update Neovim plugins\n")
		return nil
	}
	e.printf("ds upgrade: plugins\n")
	return e.Runner.Run(ctx, Cmd{
		Args: []string{nvim, "--headless", neovimUpdate, "+qa"}, Env: env,
		Dir: e.Target.Paths().Home, Stdout: e.Stderr, Stderr: e.Stderr,
	})
}

func (e *Env) upgradeSystem(ctx context.Context, dryRun bool) error {
	var steps [][]string
	env := e.Environ
	switch {
	case e.Platform.OS == "darwin" && lookPath("brew", e.lookupPath()) != "":
		steps = [][]string{{"brew", "update"}, {"brew", "upgrade"}}
		env = env.with("NONINTERACTIVE", "1", "HOMEBREW_NO_ASK", "1")
	case e.Platform.OS == "linux" && lookPath("apt-get", e.lookupPath()) != "":
		steps = [][]string{
			{"apt-get", "update"},
			{"apt-get", "upgrade", "-y", "-o", "Dpkg::Options::=--force-confdef", "-o", "Dpkg::Options::=--force-confold"},
		}
		if e.UID != 0 {
			sudo := []string{"sudo", "env", "DEBIAN_FRONTEND=noninteractive", "NEEDRESTART_MODE=a"}
			if !e.Interactive {
				sudo = slices.Insert(sudo, 1, "-n")
			}
			for i, s := range steps {
				steps[i] = append(slices.Clone(sudo), s...)
			}
		}
		env = env.with("DEBIAN_FRONTEND", "noninteractive", "NEEDRESTART_MODE", "a")
	default:
		e.printf("ds upgrade: system skipped; no supported package manager\n")
		return nil
	}
	for _, step := range steps {
		if dryRun {
			e.printf("ds upgrade: would run %s\n", strings.Join(step, " "))
			continue
		}
		e.printf("ds upgrade: %s\n", strings.Join(step, " "))
		c := Cmd{Args: step, Env: env, Stdout: e.Stderr, Stderr: e.Stderr}
		if e.Interactive {
			c.Stdin = e.Stdin
		}
		if err := e.Runner.Run(ctx, c); err != nil {
			return err
		}
	}
	return nil
}

// candidatePath is where main mode downloads the next build.
func (e *Env) candidatePath(m Manifest) string {
	return filepath.Join(e.Target.Paths().DSData(), "candidates", m.Files[e.Platform.String()].Name)
}

// FetchCandidate downloads the latest main build when it differs from the
// running one. It returns "" when ds is current.
func (e *Env) FetchCandidate(ctx context.Context, dryRun bool) (string, Manifest, error) {
	emb, ok := e.Source.(*assets.Embedded)
	if !ok {
		return "", Manifest{}, errors.New("build download requires main mode")
	}
	m, err := e.LatestManifest(ctx)
	if err != nil {
		return "", m, err
	}
	if m.Build == emb.Info.ID {
		e.printf("ds upgrade: build %s is current\n", m.Build)
		return "", m, nil
	}
	if dryRun {
		e.printf("ds upgrade: would install build %s (commit %s)\n", m.Build, short(m.Commit))
		return "", m, nil
	}
	dest := e.candidatePath(m)
	e.printf("ds upgrade: download build %s (commit %s)\n", m.Build, short(m.Commit))
	if m, err = FetchBuild(ctx, e.HTTP, e.DownloadURL, e.Platform, dest); err != nil {
		return "", m, err
	}
	return dest, m, nil
}

// ClearCandidates removes downloaded candidates after a handoff.
func (e *Env) ClearCandidates() {
	os.RemoveAll(filepath.Join(e.Target.Paths().DSData(), "candidates"))
}

func short(commit string) string {
	if len(commit) > 12 {
		return commit[:12]
	}
	return commit
}
