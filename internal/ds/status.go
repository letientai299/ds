package ds

import (
	"context"
	"fmt"
	"io"
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
}

// ComponentStatus is the tooling state of one component.
type ComponentStatus struct {
	Name    ComponentName `json:"name"`
	State   string        `json:"state"`
	Version string        `json:"version,omitempty"`
	Detail  string        `json:"detail,omitempty"`
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
	if req != nil {
		inspected := Selection{}.Union(req)
		sel, r.Inspected = inspected, &inspected
	}
	comps := e.Catalog.Expand(sel)
	if len(comps) == 0 {
		r.Summary = SummaryIncomplete
		r.Notes = append(r.Notes, "nothing selected; preview with: ds add -l core --dry-run")
		return r
	}

	mise, notes := e.findMise(ctx)
	r.Notes = append(append(r.Notes, notes...), e.legacyMiseNote()...)
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
	if emb, ok := e.Source.(*assets.Embedded); ok {
		r.Build = &BuildStatus{Running: emb.Info.ID, Current: currentBuild(e.Target.Paths().DSData())}
	}
	r.Summary = summarize(r)
	return r
}

func (e *Env) componentStatus(comp *Component, mise miseFound, facts map[string]toolFact) ComponentStatus {
	s := ComponentStatus{Name: comp.Name, State: compInstalled}
	if reason := glibcBlocker(e.Platform, comp) + toolBlocker(e.Platform, comp); reason != "" {
		return ComponentStatus{Name: comp.Name, State: compUnavailable, Detail: reason}
	}
	switch {
	case comp.Name == "mise":
		if mise.Path == "" {
			return ComponentStatus{Name: comp.Name, State: compMissing}
		}
		s.Version, s.Detail = mise.Version, mise.Path
	case len(comp.Packages) > 0:
		if missing := e.missingCommands(comp); len(missing) > 0 {
			return ComponentStatus{Name: comp.Name, State: compMissing, Detail: "missing " + strings.Join(missing, ", ")}
		}
	}
	if comp.Tool != nil {
		fact, ok := facts[comp.Tool.Name]
		switch {
		case !ok:
			return ComponentStatus{Name: comp.Name, State: compMissing, Detail: comp.Tool.Name + " is not requested"}
		case !fact.Installed:
			return ComponentStatus{Name: comp.Name, State: compMissing, Detail: comp.Tool.Name + "@" + fact.Requested + " is not installed"}
		}
		s.Version = fact.Version
		if fact.Requested != "" && !strings.HasSuffix(fact.Source.Path, "10-ds.toml") {
			s.Detail = "requested " + fact.Requested + " by " + fact.Source.Path
		}
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
	fmt.Fprintf(w, "selection: %s\n", r.Selection)
	if r.Inspected != nil {
		fmt.Fprintf(w, "inspecting: %s\n", *r.Inspected)
	}
	if r.Build != nil && (verbose || r.Build.Current != r.Build.Running) {
		fmt.Fprintf(w, "build: running %s, current %s\n", r.Build.Running, orNone(r.Build.Current))
	}
	fmt.Fprintf(w, "status: %s\n", r.Summary)
	for _, c := range r.Components {
		if verbose || c.State != compInstalled {
			fmt.Fprintf(w, "  %-11s %s%s\n", c.State, c.Name, suffix(c.Version, c.Detail))
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
