package cli

import (
	"fmt"
	"slices"
	"strings"
	"text/tabwriter"

	"github.com/spf13/cobra"

	"github.com/letientai299/ds/internal/ds"
)

func registerCompletion(cmd *cobra.Command, flag string, fn cobra.CompletionFunc) {
	if err := cmd.RegisterFlagCompletionFunc(flag, fn); err != nil {
		panic(err)
	}
}

func (a *app) catalog() (*ds.Catalog, error) {
	src, err := a.source()
	if err != nil {
		return nil, err
	}
	return ds.LoadCatalog(src)
}

func filterChoices(choices, selected []string, prefix string) ([]string, cobra.ShellCompDirective) {
	var matches []string
	for _, choice := range choices {
		name, _, _ := strings.Cut(choice, "\t")
		if strings.HasPrefix(name, prefix) && !slices.Contains(selected, name) {
			matches = append(matches, choice)
		}
	}
	return matches, cobra.ShellCompDirectiveNoFileComp
}

func componentChoices(cat *ds.Catalog) []string {
	var choices []string
	for _, name := range cat.Components() {
		choices = append(choices, string(name))
	}
	return choices
}

func layerChoices(cat *ds.Catalog) []string {
	var choices []string
	for _, layer := range cat.Layers() {
		var members []string
		for _, member := range cat.LayerMembers(layer) {
			members = append(members, string(member))
		}
		choices = append(choices, string(layer)+"\t"+strings.Join(members, ", "))
	}
	return choices
}

func (a *app) completeComponents(cmd *cobra.Command, args []string, prefix string) ([]string, cobra.ShellCompDirective) {
	layers, _ := cmd.Flags().GetStringArray("layer")
	if len(layers) > 0 {
		return nil, cobra.ShellCompDirectiveNoFileComp
	}
	cat, err := a.catalog()
	if err != nil {
		return nil, cobra.ShellCompDirectiveNoFileComp
	}
	return filterChoices(componentChoices(cat), args, prefix)
}

func (a *app) completeLayers(cmd *cobra.Command, args []string, prefix string) ([]string, cobra.ShellCompDirective) {
	if cmd.Name() == "deploy" && len(args) > 0 {
		args = args[1:]
	}
	if len(args) > 0 {
		return nil, cobra.ShellCompDirectiveNoFileComp
	}
	cat, err := a.catalog()
	if err != nil {
		return nil, cobra.ShellCompDirectiveNoFileComp
	}
	layers, _ := cmd.Flags().GetStringArray("layer")
	return filterChoices(layerChoices(cat), layers, prefix)
}

func (a *app) completeDeploy(cmd *cobra.Command, args []string, prefix string) ([]string, cobra.ShellCompDirective) {
	if len(args) == 0 {
		return nil, cobra.ShellCompDirectiveNoFileComp
	}
	return a.completeComponents(cmd, args[1:], prefix)
}

func upgradeChoices() []string {
	var choices []string
	for _, category := range ds.Categories {
		var description string
		switch category {
		case ds.CatDS:
			description = "Refresh ds and converge the saved selection"
		case ds.CatTools:
			description = "Upgrade selected mise tools"
		case ds.CatPlugins:
			description = "Update selected Neovim plugins"
		case ds.CatSystem:
			description = "Upgrade Homebrew or apt packages"
		}
		choices = append(choices, string(category)+"\t"+description)
	}
	return append(choices, "all\tUpgrade every category")
}

func completeUpgrade(cmd *cobra.Command, args []string, prefix string) ([]string, cobra.ShellCompDirective) {
	if slices.Contains(args, "all") {
		return nil, cobra.ShellCompDirectiveNoFileComp
	}
	skip, _ := cmd.Flags().GetStringArray("skip")
	selected := append(slices.Clone(args), skip...)
	if _, err := ds.ParseCategories([]string{"all"}, skip); err != nil {
		selected = append(selected, "all")
	}
	return filterChoices(upgradeChoices(), selected, prefix)
}

func completeSkip(cmd *cobra.Command, args []string, prefix string) ([]string, cobra.ShellCompDirective) {
	skip, _ := cmd.Flags().GetStringArray("skip")
	selected := slices.Clone(skip)
	if !slices.Contains(args, "all") {
		selected = append(selected, args...)
	}
	selected = append(selected, "all")
	choices, directive := filterChoices(upgradeChoices(), selected, prefix)
	choices = slices.DeleteFunc(choices, func(choice string) bool {
		name, _, _ := strings.Cut(choice, "\t")
		_, err := ds.ParseCategories(args, append(slices.Clone(skip), name))
		return err != nil
	})
	return choices, directive
}

func formatChoices(title string, choices []string) string {
	var text strings.Builder
	fmt.Fprintf(&text, "%s:\n", title)
	w := tabwriter.NewWriter(&text, 0, 0, 2, ' ', 0)
	for _, choice := range choices {
		fmt.Fprintf(w, "  %s\n", choice)
	}
	_ = w.Flush()
	return strings.TrimSuffix(text.String(), "\n")
}

func (a *app) selectorHelp(cmd *cobra.Command) {
	help := cmd.HelpFunc()
	cmd.SetHelpFunc(func(cmd *cobra.Command, args []string) {
		cat, err := a.catalog()
		if err != nil {
			help(cmd, args)
			cmd.PrintErrf("ds: %v\n", err)
			return
		}
		long := cmd.Long
		defer func() { cmd.Long = long }()
		if cmd.Long == "" {
			cmd.Long = cmd.Short
		}
		cmd.Long += "\n\nSelect components or layers, never both.\n\nComponents:\n  " +
			strings.Join(componentChoices(cat), ", ") + "\n\n" +
			formatChoices("Layers (-l, --layer)", layerChoices(cat))
		help(cmd, args)
	})
}
