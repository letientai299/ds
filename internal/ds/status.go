package ds

import (
	"context"
	"fmt"
	"io"
	"maps"
	"os"
	"slices"
	"strings"

	"github.com/letientai299/ds/internal/assets"
)

// Status summaries.
const (
	SummaryComplete   = "complete"
	SummaryIncomplete = "incomplete"
	SummaryConflict   = "conflict"
)

// Component states.
const (
	compInstalled   = "installed"
	compMissing     = "missing"
	compUnavailable = "unavailable"
)

// StatusReport describes a target without changing it.
type StatusReport struct {
	Schema     int               `json:"schema"`
	Mode       string            `json:"mode"`
	Target     string            `json:"target"`
	Selection  Selection         `json:"selection"`
	Inspected  *Selection        `json:"inspected,omitempty"`
	Summary    string            `json:"summary"`
	Components []ComponentStatus `json:"components"`
	Files      []FileStatus      `json:"files"`
	Build      *BuildStatus      `json:"build,omitempty"`
	Notes      []string          `json:"notes,omitempty"`
	Runtime    VersionReport     `json:"runtime"`
	Paths      map[string]string `json:"paths"`
	Mise       ComponentStatus   `json:"mise"`
	Platform   string            `json:"platform"`
}

// ComponentStatus is the tooling state of one component.
type ComponentStatus struct {
	Name        ComponentName     `json:"name"`
	State       string            `json:"state"`
	Version     string            `json:"version,omitempty"`
	Detail      string            `json:"detail,omitempty"`
	Requested   string            `json:"requested,omitempty"`
	Source      string            `json:"source,omitempty"`
	InstallPath string            `json:"install_path,omitempty"`
	Commands    map[string]string `json:"commands,omitempty"`
}

// FileStatus is the state of one managed path.
type FileStatus struct {
	Path   string `json:"path"`
	State  string `json:"state"`
	Detail string `json:"detail,omitempty"`
}

// BuildStatus compares the running and activated main builds.
type BuildStatus struct {
	Running string `json:"running"`
	Current string `json:"current"`
}

// Healthy reports whether status --check succeeds.
func (r StatusReport) Healthy() bool { return r.Summary == SummaryComplete }

// Status inspects saved selection, or req instead when given.
func (e *Env) Status(ctx context.Context, st State, req Request) StatusReport {
	sel := st.Selection
	r := StatusReport{Schema: 1, Mode: e.Mode(), Target: describeTarget(e.Target), Selection: st.Selection}
	r.Runtime = e.Version(ctx)
	r.Platform = e.Platform.String() + suffix(e.Platform.Libc, e.Platform.Glibc)
	for repo, rs := range e.Repos {
		if _, ok := r.Runtime.Sources[repo]; !ok {
			if _, err := os.Stat(rs.Dir); err != nil {
				r.Runtime.Sources[repo] = RepoVersion{Path: rs.Dir, Error: err.Error()}
			} else {
				r.Runtime.Sources[repo] = e.gitRevision(ctx, rs.Dir)
			}
		}
	}
	p := e.Target.Paths()
	r.Paths = map[string]string{
		"config": p.UserConfig(), "state": statePath(e.Target),
		"data": p.DSData(), "cache": p.Cache,
		"bin":         e.Target.Placeholders()["bin"],
		"mise config": e.Target.MiseConfigDir(), "mise tools": fragmentPath(e.Target),
		"mise data": p.MiseData, "mise cache": p.MiseCache, "mise state": p.MiseState,
	}
	if emb, ok := e.Source.(*assets.Embedded); ok {
		r.Build = &BuildStatus{Running: emb.Info.ID, Current: currentBuild(p.DSData())}
	}
	mise, notes := e.findMise(ctx)
	r.Mise = ComponentStatus{Name: "mise", State: compMissing}
	if mise.Path != "" {
		r.Mise.State, r.Mise.Version, r.Mise.Detail = compInstalled, mise.Version, mise.Path
	}
	r.Notes = append(notes, e.legacyMiseNote()...)
	if req != nil {
		inspected := Selection{}.Union(req)
		sel, r.Inspected = inspected, &inspected
	}
	if reason := platformBlocker(e.Platform); reason != "" {
		r.Summary = SummaryIncomplete
		r.Notes = append(r.Notes, reason)
		return r
	}
	comps := e.Catalog.Expand(sel)
	if len(comps) == 0 {
		r.Summary = SummaryIncomplete
		r.Notes = append(r.Notes, "nothing selected; preview with: ds add -l core --dry-run")
		return r
	}

	var facts map[string]toolFact
	if mise.Path != "" {
		var err error
		if facts, err = e.listTools(ctx, mise.Path); err != nil {
			r.Notes = append(r.Notes, "mise tools: "+err.Error())
		}
	}
	for _, name := range comps {
		comp, _ := e.Catalog.Component(name)
		r.Components = append(r.Components, e.componentStatus(comp, mise, facts))
	}

	scratch := &Plan{}
	entries := e.managedEntries(scratch, comps)
	if link, ok := e.miseLink(mise.Path); ok {
		entries = append(entries, link)
	}
	roots := e.legacyRoots()
	for _, entry := range entries {
		in := entry.inspect(st.Owned, roots)
		r.Files = append(r.Files, FileStatus{Path: entry.path(), State: in.State.String(), Detail: in.Reason})
	}
	for _, b := range scratch.Blockers {
		r.Files = append(r.Files, FileStatus{Path: b.Subject, State: compUnavailable, Detail: b.Reason})
	}
	r.Summary = summarize(r)
	return r
}

func (e *Env) componentStatus(comp *Component, mise miseFound, facts map[string]toolFact) ComponentStatus {
	s := ComponentStatus{Name: comp.Name, State: compInstalled}
	s.Commands = map[string]string{}
	for _, name := range comp.Commands {
		s.Commands[name] = lookPath(name, e.lookupPath())
	}
	if reason := glibcBlocker(e.Platform, comp) + toolBlocker(e.Platform, comp); reason != "" {
		s.State, s.Detail = compUnavailable, reason
		return s
	}
	switch {
	case comp.Name == "mise":
		if mise.Path == "" {
			s.State = compMissing
			return s
		}
		s.Version, s.Detail = mise.Version, mise.Path
	case len(comp.Packages) > 0:
		if missing := e.missingCommands(comp); len(missing) > 0 {
			s.State, s.Detail = compMissing, "missing "+strings.Join(missing, ", ")
			return s
		}
	}
	if comp.Tool != nil {
		fact, ok := facts[comp.Tool.Name]
		s.Requested, s.Source, s.InstallPath = fact.Requested, fact.Source.Path, fact.InstallPath
		switch {
		case !ok:
			s.State, s.Detail = compMissing, comp.Tool.Name+" is not requested"
			return s
		case !fact.Installed:
			s.State, s.Detail = compMissing, comp.Tool.Name+"@"+fact.Requested+" is not installed"
			return s
		}
		s.Version = fact.Version
	}
	return s
}

func summarize(r StatusReport) string {
	if slices.ContainsFunc(r.Files, func(f FileStatus) bool { return f.State == stateConflict.String() }) {
		return SummaryConflict
	}
	if slices.ContainsFunc(r.Components, func(c ComponentStatus) bool { return c.State != compInstalled }) ||
		slices.ContainsFunc(r.Files, func(f FileStatus) bool { return f.State != statePresent.String() }) ||
		(r.Build != nil && r.Build.Current != r.Build.Running) {
		return SummaryIncomplete
	}
	return SummaryComplete
}

// RenderStatus prints a report for people.
func RenderStatus(w io.Writer, r StatusReport, verbose bool) {
	fmt.Fprintf(w, "%s (%s mode)\n", r.Target, r.Mode)
	fmt.Fprintf(w, "platform: %s\n", r.Platform)
	fmt.Fprintf(w, "executable: %s\n", orNone(r.Runtime.Executable))
	RenderVersion(w, r.Runtime)
	for _, repo := range slices.Sorted(maps.Keys(r.Runtime.Sources)) {
		if s := r.Runtime.Sources[repo]; s.Error != "" {
			fmt.Fprintf(w, "note: %s: %s\n", repo, s.Error)
		}
	}
	for _, name := range slices.Sorted(maps.Keys(r.Paths)) {
		fmt.Fprintf(w, "%s: %s\n", name, r.Paths[name])
	}
	fmt.Fprintf(w, "mise: %s%s\n", r.Mise.State, suffix(r.Mise.Version, r.Mise.Detail))
	fmt.Fprintf(w, "selection: %s\n", r.Selection)
	if r.Inspected != nil {
		fmt.Fprintf(w, "inspecting: %s\n", *r.Inspected)
	}
	if r.Build != nil {
		fmt.Fprintf(w, "build: running %s, current %s\n", r.Build.Running, orNone(r.Build.Current))
	}
	fmt.Fprintf(w, "status: %s\n", r.Summary)
	for _, c := range r.Components {
		fmt.Fprintf(w, "  %-11s %s%s\n", c.State, c.Name, suffix(c.Version, c.Detail))
		if c.Source != "" {
			fmt.Fprintf(w, "    request: %s (%s)\n", c.Requested, c.Source)
		}
		if c.InstallPath != "" {
			fmt.Fprintf(w, "    install: %s\n", c.InstallPath)
		}
		for _, name := range slices.Sorted(maps.Keys(c.Commands)) {
			fmt.Fprintf(w, "    %s: %s\n", name, orNone(c.Commands[name]))
		}
	}
	for _, f := range r.Files {
		if verbose || f.State != statePresent.String() {
			fmt.Fprintf(w, "  %-11s %s%s\n", f.State, f.Path, suffix("", f.Detail))
		}
	}
	for _, n := range r.Notes {
		fmt.Fprintf(w, "note: %s\n", n)
	}
	switch r.Summary {
	case SummaryIncomplete:
		if !r.Selection.Empty() || r.Inspected != nil {
			fmt.Fprintln(w, "preview: ds add --dry-run")
		}
	case SummaryConflict:
		fmt.Fprintln(w, "preview: ds add --force --dry-run")
	}
}

func suffix(version, detail string) string {
	var parts []string
	if version != "" {
		parts = append(parts, version)
	}
	if detail != "" {
		parts = append(parts, detail)
	}
	if len(parts) == 0 {
		return ""
	}
	return " (" + strings.Join(parts, "; ") + ")"
}

func orNone(s string) string {
	if s == "" {
		return "none"
	}
	return s
}

// RenderPlan prints a plan preview.
func RenderPlan(w io.Writer, p *Plan) {
	fmt.Fprintf(w, "%s\n", describeTarget(p.Target))
	fmt.Fprintf(w, "selection: %s\n", p.Selection)
	fmt.Fprintf(w, "components: %s\n", joinNames(p.Components, " "))
	if len(p.Actions) == 0 && len(p.Blockers) == 0 {
		fmt.Fprintln(w, "nothing to do")
	}
	for _, a := range p.Actions {
		fmt.Fprintf(w, "  %s\n", a.Describe())
	}
	if len(p.Blockers) > 0 {
		fmt.Fprintln(w, "blocked:")
		for _, b := range p.Blockers {
			fmt.Fprintf(w, "  %s\n", b)
		}
	}
	for _, n := range p.Notes {
		fmt.Fprintf(w, "note: %s\n", n)
	}
}
