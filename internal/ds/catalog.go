package ds

import (
	"bytes"
	"cmp"
	"errors"
	"fmt"
	"maps"
	"regexp"
	"slices"
	"strings"

	"github.com/pelletier/go-toml/v2"

	"github.com/letientai299/ds/internal/assets"
)

// ComponentName identifies a catalog component.
type ComponentName string

// LayerName identifies a catalog layer.
type LayerName string

// Catalog is the validated component and layer declaration.
type Catalog struct {
	layers     map[LayerName][]ComponentName
	layerOrder []LayerName
	components map[ComponentName]*Component
	order      []ComponentName
}

// Component declares one selectable unit of tooling and configuration.
type Component struct {
	Name     ComponentName
	Commands []string
	Requires []ComponentName
	// Packages provide Commands natively.
	Packages map[string][]string
	// Prerequisites are native libraries a tool needs before it runs.
	Prerequisites map[string][]string
	Tool          *Tool
	Links         []LinkSpec
	Blocks        []BlockSpec
	Helper        *HelperSpec
	Glibc         string
}

// Tool is a mise tool request owned by a component.
type Tool struct {
	Name string
	// Spec holds every tool option except the name.
	Spec map[string]any
}

// LinkSpec declares a symlink from a target placeholder path to an asset.
type LinkSpec struct {
	Target string
	Source assets.Ref
}

// BlockSpec declares a managed block appended to a user file.
type BlockSpec struct {
	Target string
	Text   string
}

// HelperSpec declares a Go helper built from a configuration repository.
type HelperSpec struct {
	Repo    assets.Repo
	Package string
	Output  string
}

// Package managers with declared native packages.
const (
	ManagerApt  = "apt"
	ManagerBrew = "brew"
)

var (
	namePattern   = regexp.MustCompile(`^[a-z][a-z0-9-]*$`)
	targetPattern = regexp.MustCompile(`^\{([a-z]+)\}(/.*)?$`)
	targetKeys    = []string{"bin", "ds", "zshrc", "gitconfig", "ssh", "nvim", "tmux"}
)

type rawCatalog struct {
	Layers     map[string][]string     `toml:"layers"`
	Components map[string]rawComponent `toml:"components"`
}

type rawComponent struct {
	Commands []string            `toml:"commands"`
	Requires []string            `toml:"requires"`
	Packages map[string][]string `toml:"packages"`
	Prereqs  map[string][]string `toml:"prerequisites"`
	Tool     map[string]any      `toml:"tool"`
	Links    []rawLink           `toml:"links"`
	Blocks   []BlockSpec         `toml:"blocks"`
	Helper   *rawHelper          `toml:"helper"`
	Glibc    string              `toml:"glibc"`
}

type rawLink struct {
	Target string `toml:"target"`
	Source string `toml:"source"`
}

type rawHelper struct {
	Repo    string `toml:"repo"`
	Package string `toml:"package"`
	Output  string `toml:"output"`
}

// ParseCatalog decodes and validates catalog TOML.
func ParseCatalog(data []byte) (*Catalog, error) {
	var raw rawCatalog
	decoder := toml.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&raw); err != nil {
		return nil, fmt.Errorf("decode catalog: %w", err)
	}
	c := &Catalog{
		layers:     map[LayerName][]ComponentName{},
		components: map[ComponentName]*Component{},
	}
	var errs []error
	for name, rc := range raw.Components {
		comp, err := parseComponent(name, rc)
		if err != nil {
			errs = append(errs, err)
			continue
		}
		c.components[comp.Name] = comp
	}
	for _, name := range slices.Sorted(maps.Keys(raw.Layers)) {
		if !namePattern.MatchString(name) {
			errs = append(errs, fmt.Errorf("invalid layer name %q", name))
			continue
		}
		layer := LayerName(name)
		if len(raw.Layers[name]) == 0 {
			errs = append(errs, fmt.Errorf("layer %s is empty", name))
		}
		seen := map[ComponentName]bool{}
		for _, member := range raw.Layers[name] {
			comp := ComponentName(member)
			if seen[comp] {
				errs = append(errs, fmt.Errorf("layer %s lists %s twice", name, member))
			}
			seen[comp] = true
			if _, ok := c.components[comp]; !ok {
				errs = append(errs, fmt.Errorf("layer %s: unknown component %s", name, member))
			}
			c.layers[layer] = append(c.layers[layer], comp)
		}
		c.layerOrder = append(c.layerOrder, layer)
	}
	errs = append(errs, c.validate()...)
	if err := errors.Join(errs...); err != nil {
		return nil, err
	}
	c.order = c.componentOrder()
	return c, nil
}

func parseComponent(name string, rc rawComponent) (*Component, error) {
	if !namePattern.MatchString(name) {
		return nil, fmt.Errorf("invalid component name %q", name)
	}
	comp := &Component{
		Name:          ComponentName(name),
		Commands:      rc.Commands,
		Packages:      rc.Packages,
		Prerequisites: rc.Prereqs,
		Blocks:        rc.Blocks,
		Glibc:         rc.Glibc,
	}
	var errs []error
	if len(rc.Commands) == 0 {
		errs = append(errs, fmt.Errorf("component %s declares no commands", name))
	}
	for _, req := range rc.Requires {
		comp.Requires = append(comp.Requires, ComponentName(req))
	}
	for _, decl := range []map[string][]string{rc.Packages, rc.Prereqs} {
		for manager := range decl {
			if manager != ManagerApt && manager != ManagerBrew {
				errs = append(errs, fmt.Errorf("component %s: unsupported package manager %s", name, manager))
			}
		}
	}
	if len(rc.Prereqs) > 0 && rc.Tool == nil {
		errs = append(errs, fmt.Errorf("component %s: prerequisites require a tool", name))
	}
	if rc.Tool != nil {
		toolName, _ := rc.Tool["name"].(string)
		if toolName == "" {
			errs = append(errs, fmt.Errorf("component %s: tool requires a name", name))
		}
		if _, ok := rc.Tool["version"].(string); !ok {
			errs = append(errs, fmt.Errorf("component %s: tool requires a version", name))
		}
		spec := maps.Clone(rc.Tool)
		delete(spec, "name")
		comp.Tool = &Tool{Name: toolName, Spec: spec}
	}
	for _, link := range rc.Links {
		ref, err := assets.ParseRef(link.Source)
		if err != nil {
			errs = append(errs, fmt.Errorf("component %s: %w", name, err))
		}
		comp.Links = append(comp.Links, LinkSpec{Target: link.Target, Source: ref})
	}
	if rc.Helper != nil {
		repo := assets.Repo(rc.Helper.Repo)
		if !repo.Valid() || rc.Helper.Package == "" || rc.Helper.Output == "" {
			errs = append(errs, fmt.Errorf("component %s: invalid helper", name))
		}
		comp.Helper = &HelperSpec{Repo: repo, Package: rc.Helper.Package, Output: rc.Helper.Output}
	}
	return comp, errors.Join(errs...)
}

func (c *Catalog) validate() []error {
	var errs []error
	tools := map[string]ComponentName{}
	targets := map[string]ComponentName{}
	claim := func(owner ComponentName, target string) {
		if prev, ok := targets[target]; ok {
			errs = append(errs, fmt.Errorf("%s and %s both own %s", prev, owner, target))
		}
		targets[target] = owner
	}
	for _, name := range slices.Sorted(maps.Keys(c.components)) {
		comp := c.components[name]
		for _, req := range comp.Requires {
			if _, ok := c.components[req]; !ok {
				errs = append(errs, fmt.Errorf("component %s requires unknown component %s", name, req))
			}
		}
		if comp.Tool != nil {
			if prev, ok := tools[comp.Tool.Name]; ok {
				errs = append(errs, fmt.Errorf("%s and %s both own tool %s", prev, name, comp.Tool.Name))
			}
			tools[comp.Tool.Name] = name
			if !slices.Contains(comp.Requires, "mise") {
				errs = append(errs, fmt.Errorf("component %s has a mise tool but does not require mise", name))
			}
		}
		for _, link := range comp.Links {
			if err := validTarget(link.Target); err != nil {
				errs = append(errs, fmt.Errorf("component %s: %w", name, err))
			}
			claim(name, link.Target)
		}
		for _, block := range comp.Blocks {
			if err := validTarget(block.Target); err != nil {
				errs = append(errs, fmt.Errorf("component %s: %w", name, err))
			}
			if strings.TrimSpace(block.Text) == "" {
				errs = append(errs, fmt.Errorf("component %s: empty block for %s", name, block.Target))
			}
			claim(name, block.Target)
		}
	}
	if cycle := c.findCycle(); cycle != nil {
		errs = append(errs, fmt.Errorf("dependency cycle: %s", joinNames(cycle, " -> ")))
	}
	return errs
}

func validTarget(target string) error {
	m := targetPattern.FindStringSubmatch(target)
	if m == nil || !slices.Contains(targetKeys, m[1]) {
		return fmt.Errorf("invalid target %q", target)
	}
	return nil
}

func (c *Catalog) findCycle() []ComponentName {
	const (
		visiting = 1
		done     = 2
	)
	marks := map[ComponentName]int{}
	var stack []ComponentName
	var visit func(ComponentName) []ComponentName
	visit = func(name ComponentName) []ComponentName {
		switch marks[name] {
		case visiting:
			start := slices.Index(stack, name)
			return append(slices.Clone(stack[start:]), name)
		case done:
			return nil
		}
		marks[name] = visiting
		stack = append(stack, name)
		if comp, ok := c.components[name]; ok {
			for _, req := range comp.Requires {
				if cycle := visit(req); cycle != nil {
					return cycle
				}
			}
		}
		stack = stack[:len(stack)-1]
		marks[name] = done
		return nil
	}
	for _, name := range slices.Sorted(maps.Keys(c.components)) {
		if cycle := visit(name); cycle != nil {
			return cycle
		}
	}
	return nil
}

// componentOrder lists components by first layer appearance, then by name.
func (c *Catalog) componentOrder() []ComponentName {
	var order []ComponentName
	seen := map[ComponentName]bool{}
	for _, layer := range c.layerOrder {
		for _, comp := range c.layers[layer] {
			if !seen[comp] {
				seen[comp] = true
				order = append(order, comp)
			}
		}
	}
	for _, name := range slices.Sorted(maps.Keys(c.components)) {
		if !seen[name] {
			order = append(order, name)
		}
	}
	return order
}

// Layers returns layer names in declaration order.
func (c *Catalog) Layers() []LayerName { return slices.Clone(c.layerOrder) }

// LayerMembers returns the components of a layer.
func (c *Catalog) LayerMembers(layer LayerName) []ComponentName {
	return slices.Clone(c.layers[layer])
}

// Components returns component names in catalog order.
func (c *Catalog) Components() []ComponentName { return slices.Clone(c.order) }

// Component returns a component declaration.
func (c *Catalog) Component(name ComponentName) (*Component, bool) {
	comp, ok := c.components[name]
	return comp, ok
}

// HasLayer reports whether a layer exists.
func (c *Catalog) HasLayer(name LayerName) bool {
	_, ok := c.layers[name]
	return ok
}

// Expand resolves layers, components, and dependencies in catalog order.
func (c *Catalog) Expand(sel Selection) []ComponentName {
	want := map[ComponentName]bool{}
	var add func(ComponentName)
	add = func(name ComponentName) {
		comp, ok := c.components[name]
		if !ok || want[name] {
			return
		}
		want[name] = true
		for _, req := range comp.Requires {
			add(req)
		}
	}
	for _, layer := range sel.Layers {
		for _, comp := range c.layers[layer] {
			add(comp)
		}
	}
	for _, comp := range sel.Components {
		add(comp)
	}
	return slices.DeleteFunc(slices.Clone(c.order), func(name ComponentName) bool { return !want[name] })
}

func joinNames[T ~string](names []T, sep string) string {
	parts := make([]string, len(names))
	for i, n := range names {
		parts[i] = string(n)
	}
	return strings.Join(parts, sep)
}

func sortedUnique[T cmp.Ordered](items []T) []T {
	out := slices.Clone(items)
	slices.Sort(out)
	return slices.Compact(out)
}
