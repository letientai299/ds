package ds

import (
	"context"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/letientai299/ds/internal/assets"
)

// Action is one planned effect. Each variant is a concrete type.
type Action interface {
	Describe() string
	isAction()
}

// StageBuild extracts this main build beneath the data directory.
type StageBuild struct{ ID, Dir string }

// FetchMise downloads the pinned mise.
type FetchMise struct {
	Version  string
	Download Download
	Path     string
}

// InstallPackages installs native packages through mise's bootstrap.
type InstallPackages struct {
	Mise     string
	Manager  string
	Packages []string
	Sudo     bool
}

// CloneRepo clones a configuration repository. Managed clones are shallow.
type CloneRepo struct {
	Repo    assets.Repo
	URL     string
	Dir     string
	Shallow bool
}

// BuildHelper compiles a configuration repository's Go helper.
type BuildHelper struct {
	Mise    string
	Dir     string
	Package string
	Output  string
}

// FileChange converges one managed path.
type FileChange struct {
	Entry  managed
	Expect fileState
	// Backup preserves conflicting content first.
	Backup string
}

// InstallTools installs mise tools from the effective global configuration.
type InstallTools struct {
	Mise  string
	Tools []string
}

// BootstrapNeovim installs startup plugins headlessly.
type BootstrapNeovim struct {
	Mise    string
	AppName string
}

// ActivateBuild switches the current main build.
type ActivateBuild struct{ ID string }

func (StageBuild) isAction()      {}
func (FetchMise) isAction()       {}
func (InstallPackages) isAction() {}
func (CloneRepo) isAction()       {}
func (BuildHelper) isAction()     {}
func (FileChange) isAction()      {}
func (InstallTools) isAction()    {}
func (BootstrapNeovim) isAction() {}
func (ActivateBuild) isAction()   {}

func (a StageBuild) Describe() string { return "stage build " + a.ID + " in " + a.Dir }
func (a FetchMise) Describe() string {
	return fmt.Sprintf("download mise %s to %s", a.Version, a.Path)
}
func (a InstallPackages) Describe() string {
	sudo := ""
	if a.Sudo {
		sudo = " with sudo"
	}
	return fmt.Sprintf("install %s packages%s: %s", a.Manager, sudo, strings.Join(a.Packages, " "))
}
func (a CloneRepo) Describe() string { return "clone " + a.URL + " into " + a.Dir }
func (a BuildHelper) Describe() string {
	return "build " + filepath.Join(a.Dir, a.Output) + " from " + a.Package
}
func (a FileChange) Describe() string {
	verb := map[fileState]string{stateMissing: "create", stateStale: "update", stateConflict: "replace"}[a.Expect]
	s := verb + " " + a.Entry.describe()
	if a.Backup != "" {
		s += " (backup " + a.Backup + ")"
	}
	return s
}
func (a InstallTools) Describe() string {
	return "install mise tools: " + strings.Join(a.Tools, " ")
}
func (a BootstrapNeovim) Describe() string { return "install Neovim startup plugins" }
func (a ActivateBuild) Describe() string   { return "activate build " + a.ID }

// Blocker prevents a plan from executing.
type Blocker struct {
	Subject string
	Reason  string
	Remedy  string
}

func (b Blocker) String() string {
	s := b.Subject + ": " + b.Reason
	if b.Remedy != "" {
		s += "; " + b.Remedy
	}
	return s
}

// Plan is one convergence, used for both preview and execution.
type Plan struct {
	Target     Target
	Selection  Selection
	Components []ComponentName
	Actions    []Action
	Blockers   []Blocker
	// Notes are facts the plan could not resolve without effects.
	Notes []string
}

func (p *Plan) block(subject, reason, remedy string) {
	p.Blockers = append(p.Blockers, Blocker{Subject: subject, Reason: reason, Remedy: remedy})
}

// AddOptions tune convergence.
type AddOptions struct {
	Force      bool
	NoPackages bool
	// KeepConflicts preserves user edits during upgrades.
	KeepConflicts bool
	// SkipPackages leaves native packages alone without requiring them,
	// as a trial does.
	SkipPackages bool
	// SkipTools defers tool installation, as a trial does.
	SkipTools bool
}

// BuildPlan computes the convergence of saved selection plus req.
func (e *Env) BuildPlan(ctx context.Context, st State, req Request, opt AddOptions) *Plan {
	sel := st.Selection
	if req != nil {
		sel = sel.Union(req)
	}
	comps := e.Catalog.Expand(sel)
	p := &Plan{Target: e.Target, Selection: sel, Components: comps}
	if reason := platformBlocker(e.Platform); reason != "" {
		p.block("platform", reason, "use macOS or a glibc Linux distribution")
		return p
	}

	emb, embedded := e.Source.(*assets.Embedded)
	if embedded && !buildComplete(e.buildDir(emb.Info.ID)) {
		p.Actions = append(p.Actions, StageBuild{ID: emb.Info.ID, Dir: e.buildDir(emb.Info.ID)})
	}
	for _, name := range comps {
		comp, _ := e.Catalog.Component(name)
		if reason := glibcBlocker(e.Platform, comp); reason != "" {
			p.block(string(name), reason, "select it on a supported host")
		}
		if reason := toolBlocker(e.Platform, comp); reason != "" {
			p.block(string(name), reason, "")
		}
	}

	var entries []managed
	packages := e.planPackages(ctx, p, comps, opt)
	needMise := packages != nil || slices.ContainsFunc(comps, func(n ComponentName) bool {
		comp, _ := e.Catalog.Component(n)
		return n == "mise" || slices.Contains(comp.Requires, "mise")
	})
	mise, fetched := "", false
	if needMise {
		mise, fetched = e.planMise(ctx, p)
		if link, ok := e.miseLink(mise); ok {
			entries = append(entries, link)
		}
	}
	if packages != nil {
		packages.Mise = mise
		p.Actions = append(p.Actions, *packages)
	}
	e.planRepos(p, comps)
	e.planHelpers(p, comps, mise)

	entries = append(entries, e.managedEntries(p, comps)...)
	e.planFiles(p, st, entries, opt)
	// Links resolve through current, so tools and plugins that read assets
	// run after activation.
	if embedded && currentBuild(e.Target.Paths().DSData()) != emb.Info.ID {
		p.Actions = append(p.Actions, ActivateBuild{ID: emb.Info.ID})
	}
	if !opt.SkipTools {
		e.planTools(ctx, p, comps, mise, fetched, opt)
	}
	return p
}

// planMise reuses a compatible mise or plans fetching the pinned one.
func (e *Env) planMise(ctx context.Context, p *Plan) (mise string, fetched bool) {
	found, notes := e.findMise(ctx)
	p.Notes = append(append(p.Notes, notes...), e.legacyMiseNote()...)
	if found.Path != "" {
		return found.Path, false
	}
	asset, ok := e.Mise.Assets[e.Platform.MiseKey()]
	if !ok {
		p.block("mise", "no pinned mise for "+e.Platform.MiseKey(), "install mise "+e.Mise.Minimum+"+ first")
	}
	p.Actions = append(p.Actions, FetchMise{Version: e.Mise.Version, Download: asset, Path: e.fetchedMise()})
	return e.fetchedMise(), true
}

// planTools installs requested tools that mise reports missing, then
// bootstraps Neovim plugins once.
func (e *Env) planTools(ctx context.Context, p *Plan, comps []ComponentName, mise string, fetched bool, opt AddOptions) {
	if names := toolNames(e.Catalog, comps); len(names) > 0 {
		pending := names
		if !fetched && mise != "" && !e.changesFile(p, fragmentPath(e.Target)) {
			if facts, err := e.listTools(ctx, mise); err == nil {
				pending = slices.DeleteFunc(slices.Clone(names), func(n string) bool {
					fact, requested := facts[n]
					return fact.Installed || (opt.KeepConflicts && !requested)
				})
			} else if opt.KeepConflicts {
				p.block("mise", err.Error(), "")
			}
		} else {
			p.Notes = append(p.Notes, "tool versions resolve when mise installs them")
		}
		if len(pending) > 0 {
			p.Actions = append(p.Actions, InstallTools{Mise: mise, Tools: pending})
		}
	}
	lazy := filepath.Join(e.Target.Paths().Data, e.Target.NvimAppName(), "lazy", "lazy.nvim")
	if slices.Contains(comps, "neovim") && !exists(lazy) {
		p.Actions = append(p.Actions, BootstrapNeovim{Mise: mise, AppName: e.Target.NvimAppName()})
	}
}

// changesFile reports whether the plan writes target.
func (e *Env) changesFile(p *Plan, target string) bool {
	return slices.ContainsFunc(p.Actions, func(a Action) bool {
		fc, ok := a.(FileChange)
		return ok && fc.Entry.path() == target
	})
}

// miseLink puts a ds-fetched mise onto PATH; other installs stay as they are.
func (e *Env) miseLink(mise string) (managedLink, bool) {
	if mise == "" || mise != e.fetchedMise() {
		return managedLink{}, false
	}
	return managedLink{Target: filepath.Join(e.Target.Placeholders()["bin"], "mise"), Source: mise}, true
}

// lookupPath is where commands are searched, including mise shims.
func (e *Env) lookupPath() string {
	return strings.Join([]string{
		e.Target.Placeholders()["bin"],
		e.Target.Paths().Bin(),
		filepath.Join(e.Target.Paths().MiseData, "shims"),
		e.Environ.get("PATH"),
		e.SystemPath,
	}, ":")
}

func (e *Env) missingCommands(comp *Component) []string {
	var missing []string
	for _, c := range comp.Commands {
		if lookPath(c, e.lookupPath()) == "" {
			missing = append(missing, c)
		}
	}
	return missing
}

// planPackages returns the native packages to install, or nil.
func (e *Env) planPackages(ctx context.Context, p *Plan, comps []ComponentName, opt AddOptions) *InstallPackages {
	if opt.SkipPackages {
		return nil
	}
	manager, managerKey := "", ""
	switch e.Platform.OS {
	case "darwin":
		managerKey = ManagerBrew
		if lookPath("brew", e.lookupPath()) != "" {
			manager = "brew"
		}
	case "linux":
		managerKey = ManagerApt
		if lookPath("apt-get", e.lookupPath()) != "" {
			manager = "apt"
		}
	}
	var pkgs []string
	for _, name := range comps {
		comp, _ := e.Catalog.Component(name)
		native := len(comp.Packages) > 0
		if !native && len(comp.Prerequisites[managerKey]) == 0 {
			continue
		}
		missing := e.missingCommands(comp)
		if len(missing) == 0 {
			continue
		}
		if !native {
			// Prerequisites accompany the first tool installation.
			prereqs := comp.Prerequisites[managerKey]
			switch {
			case opt.NoPackages:
			case manager == "":
				p.Notes = append(p.Notes, fmt.Sprintf("%s needs %s", name, strings.Join(prereqs, " ")))
			default:
				pkgs = append(pkgs, prereqs...)
			}
			continue
		}
		list := comp.Packages[managerKey]
		switch {
		case opt.NoPackages:
			p.block(string(name), "missing "+strings.Join(missing, ", "), "install it first or omit --no-packages")
		case len(list) == 0:
			p.block(string(name), "missing "+strings.Join(missing, ", ")+"; no "+e.Platform.OS+" package is declared",
				"install it first and rerun with --no-packages")
		case manager == "":
			remedy := "install " + strings.Join(list, " ") + " and rerun with --no-packages"
			if e.Platform.OS == "darwin" {
				remedy = "install Homebrew (https://brew.sh) or " + remedy
			}
			p.block(string(name), "no supported package manager", remedy)
		default:
			pkgs = append(pkgs, list...)
		}
	}
	if len(pkgs) == 0 {
		return nil
	}
	pkgs = sortedUnique(pkgs)
	sudo := e.Platform.OS == "linux" && e.UID != 0
	if sudo {
		remedy := "run as root, or install " + strings.Join(pkgs, " ") + " and rerun with --no-packages"
		switch {
		case lookPath("sudo", e.lookupPath()) == "":
			p.block("packages", "installing packages needs root or sudo", remedy)
		case !e.Interactive:
			c := Cmd{Args: []string{"sudo", "-n", "true"}, Env: e.Environ, Timeout: 5 * time.Second}
			if _, err := output(ctx, e.Runner, c); err != nil {
				p.block("packages", "non-interactive runs need cached or passwordless sudo", remedy)
			}
		}
	}
	p.Notes = append(p.Notes, "package availability is checked by "+manager+" during installation")
	return &InstallPackages{Manager: manager, Packages: pkgs, Sudo: sudo}
}

// planRepos clones configuration repositories that selected components
// use and that are not on disk yet.
func (e *Env) planRepos(p *Plan, comps []ComponentName) {
	var repos []assets.Repo
	for _, name := range comps {
		comp, _ := e.Catalog.Component(name)
		for _, link := range comp.Links {
			repos = append(repos, link.Source.Repo)
		}
		if comp.Helper != nil {
			repos = append(repos, comp.Helper.Repo)
		}
	}
	for _, repo := range assets.ConfigRepos {
		src := e.Repos[repo]
		if !slices.Contains(repos, repo) || exists(src.Dir) {
			continue
		}
		p.Actions = append(p.Actions, CloneRepo{Repo: repo, URL: src.URL, Dir: src.Dir, Shallow: src.Managed})
	}
}

// cloning reports whether the plan clones repo.
func (p *Plan) cloning(repo assets.Repo) bool {
	return slices.ContainsFunc(p.Actions, func(a Action) bool {
		c, ok := a.(CloneRepo)
		return ok && c.Repo == repo
	})
}

// planHelpers builds helpers that are missing or older than their sources.
func (e *Env) planHelpers(p *Plan, comps []ComponentName, mise string) {
	for _, name := range comps {
		comp, _ := e.Catalog.Component(name)
		if comp.Helper == nil {
			continue
		}
		dir := e.Repos[comp.Helper.Repo].Dir
		cloning := p.cloning(comp.Helper.Repo)
		if !cloning && (!exists(dir) || helperFresh(dir, filepath.Join(dir, filepath.FromSlash(comp.Helper.Output)))) {
			continue
		}
		p.Actions = append(p.Actions, BuildHelper{Mise: mise, Dir: dir, Package: comp.Helper.Package, Output: comp.Helper.Output})
	}
}

func helperFresh(dir, out string) bool {
	info, err := os.Stat(out)
	if err != nil {
		return false
	}
	built := info.ModTime()
	stale := false
	err = filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err != nil || stale {
			return filepath.SkipAll
		}
		if d.IsDir() && strings.HasPrefix(d.Name(), ".") && p != dir {
			return filepath.SkipDir
		}
		if name := d.Name(); strings.HasSuffix(name, ".go") || name == "go.mod" || name == "go.sum" {
			if fi, err := d.Info(); err == nil && fi.ModTime().After(built) {
				stale = true
			}
		}
		return nil
	})
	return err == nil && !stale
}

// managedEntries lists desired files of comps; unavailable sources block.
func (e *Env) managedEntries(p *Plan, comps []ComponentName) []managed {
	bin := e.Target.Placeholders()["bin"]
	entries := []managed{managedLink{Target: filepath.Join(bin, "ds"), Source: e.dsExecutable()}}
	for _, name := range comps {
		comp, _ := e.Catalog.Component(name)
		for _, link := range comp.Links {
			target, ok := expand(e.Target, link.Target)
			if !ok {
				continue
			}
			if !e.sourceAvailable(link.Source) && !p.cloning(link.Source.Repo) && !e.helperOutput(p, comp, link.Source) {
				p.block(string(name), "missing source "+e.assetPath(link.Source), "")
				continue
			}
			entries = append(entries, managedLink{Target: target, Source: e.assetPath(link.Source)})
		}
		for _, block := range comp.Blocks {
			target, ok := expand(e.Target, block.Target)
			if !ok {
				continue
			}
			entries = append(entries, managedBlock{Target: target, Body: expandText(e.Target, block.Text)})
		}
		for _, spec := range comp.JSON {
			target, ok := expand(e.Target, spec.Target)
			if !ok {
				continue
			}
			set := map[string]any{}
			for key, value := range spec.Set {
				set[key] = expandValue(e.Target, value)
			}
			entries = append(entries, managedJSON{Target: target, Set: set})
		}
	}
	fragment, err := renderFragment(e.Catalog, comps, e.assetDir())
	if err != nil {
		p.block("mise", "render tool configuration: "+err.Error(), "")
	} else if fragment != nil {
		entries = append(entries, managedFile{Target: fragmentPath(e.Target), Content: fragment, Mode: 0o644})
	}
	ds := e.Target.Placeholders()["ds"]
	if slices.Contains(comps, "zsh") && len(e.Completion) > 0 {
		entries = append(entries, managedFile{Target: filepath.Join(ds, "completions", "_ds"), Content: e.Completion, Mode: 0o644})
	}
	if trial, ok := e.Target.(TrialTarget); ok && slices.Contains(comps, "tmux") {
		entries = append(entries, managedFile{
			Target:  filepath.Join(trial.Bin(), "tmux"),
			Content: []byte(trialTmux(filepath.Join(trial.TmuxConfigDir(), "tmux.conf"))),
			Mode:    0o755,
		})
	}
	return entries
}

// helperOutput reports a helper link whose binary the plan builds.
func (e *Env) helperOutput(p *Plan, comp *Component, ref assets.Ref) bool {
	return comp.Helper != nil && ref.Repo == comp.Helper.Repo && ref.Path == comp.Helper.Output &&
		slices.ContainsFunc(p.Actions, func(a Action) bool {
			b, ok := a.(BuildHelper)
			return ok && b.Dir == e.Repos[ref.Repo].Dir && b.Output == ref.Path
		})
}

func (e *Env) planFiles(p *Plan, st State, entries []managed, opt AddOptions) {
	backups := filepath.Join(e.Target.StateDir(), "backups", e.now().UTC().Format("20060102T150405Z"))
	roots := e.legacyRoots()
	for _, entry := range entries {
		in := entry.inspect(st.Owned, roots)
		switch in.State {
		case statePresent:
			continue
		case stateMissing, stateStale:
			p.Actions = append(p.Actions, FileChange{Entry: entry, Expect: in.State})
		case stateConflict:
			switch {
			case opt.KeepConflicts && !in.Locked:
				p.Notes = append(p.Notes, "preserving conflict: "+entry.path())
			case in.Locked:
				p.block(entry.path(), in.Reason, "")
			case !opt.Force:
				p.block(entry.path(), in.Reason, "rerun with --force to back it up and replace it")
			default:
				p.Actions = append(p.Actions, FileChange{
					Entry: entry, Expect: stateConflict,
					Backup: backupPath(backups, e.Target.Paths().Home, entry.path()),
				})
			}
		}
	}
}

// trialTmux runs tmux on a dedicated socket with the trial configuration.
func trialTmux(conf string) string {
	return `#!/bin/sh
# Managed by ds: trial tmux uses its own server and configuration.
self=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
real=
IFS=:
for dir in $PATH; do
	[ "$dir" = "$self" ] && continue
	if [ -x "$dir/tmux" ]; then
		real=$dir/tmux
		break
	fi
done
unset IFS
[ -n "$real" ] || {
	echo 'tmux: not installed' >&2
	exit 127
}
if [ "${1:-}" = -L ]; then
	shift 2
fi
exec "$real" -L ds-trial -f ` + shellQuote(conf) + ` "$@"
`
}

// shellQuote quotes s for POSIX shells.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}
