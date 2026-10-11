package ds

import (
	"fmt"
	"slices"
	"strings"
)

// UsageError reports invalid input; the CLI exits with status 2.
type UsageError struct{ Msg string }

func (e *UsageError) Error() string { return e.Msg }

func usagef(format string, args ...any) error {
	return &UsageError{Msg: fmt.Sprintf(format, args...)}
}

// Request is an explicit selection: LayerRequest or ComponentRequest.
type Request interface {
	selection() Selection
	isRequest()
}

// LayerRequest selects whole layers.
type LayerRequest struct{ Layers []LayerName }

// ComponentRequest selects individual components.
type ComponentRequest struct{ Components []ComponentName }

func (LayerRequest) isRequest()     {}
func (ComponentRequest) isRequest() {}

func (r LayerRequest) selection() Selection     { return Selection{Layers: r.Layers} }
func (r ComponentRequest) selection() Selection { return Selection{Components: r.Components} }

// Selection is the set of explicitly selected layers and components.
type Selection struct {
	Layers     []LayerName     `json:"layers"`
	Components []ComponentName `json:"components"`
}

// Union adds r to s without duplicates.
func (s Selection) Union(r Request) Selection {
	add := r.selection()
	return Selection{
		Layers:     sortedUnique(append(slices.Clone(s.Layers), add.Layers...)),
		Components: sortedUnique(append(slices.Clone(s.Components), add.Components...)),
	}
}

// Empty reports whether nothing is selected.
func (s Selection) Empty() bool { return len(s.Layers) == 0 && len(s.Components) == 0 }

func (s Selection) String() string {
	var parts []string
	for _, l := range s.Layers {
		parts = append(parts, "-l "+string(l))
	}
	for _, c := range s.Components {
		parts = append(parts, string(c))
	}
	if len(parts) == 0 {
		return "nothing"
	}
	return strings.Join(parts, " ")
}

// ParseRequest validates selectors. Layers and components are mutually
// exclusive; a nil request means none were given.
func ParseRequest(c *Catalog, layers, components []string) (Request, error) {
	if len(layers) > 0 && len(components) > 0 {
		return nil, usagef("select layers or components, not both (got --layer %s and %s)",
			strings.Join(layers, " --layer "), strings.Join(components, " "))
	}
	if len(layers) > 0 {
		var out []LayerName
		for _, name := range layers {
			layer := LayerName(name)
			if !c.HasLayer(layer) {
				return nil, usagef("unknown layer %q (layers: %s)", name, joinNames(c.Layers(), ", "))
			}
			out = append(out, layer)
		}
		return LayerRequest{Layers: sortedUnique(out)}, nil
	}
	if len(components) > 0 {
		var out []ComponentName
		for _, name := range components {
			comp := ComponentName(name)
			if _, ok := c.Component(comp); ok {
				out = append(out, comp)
				continue
			}
			if c.HasLayer(LayerName(name)) {
				return nil, usagef("%q is a layer; use --layer %s", name, name)
			}
			return nil, usagef("unknown component %q (components: %s)", name, joinNames(c.Components(), ", "))
		}
		return ComponentRequest{Components: sortedUnique(out)}, nil
	}
	return nil, nil
}
