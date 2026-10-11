package ds

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// PrepareTrial converges trial configuration without installing packages
// or tools and returns the environment for the trial shell. Missing tools
// are reported; `ds add` inside the trial installs them.
func (e *Env) PrepareTrial(ctx context.Context, home State) (envList, error) {
	trial, ok := e.Target.(TrialTarget)
	if !ok {
		return nil, errors.New("trial requires a trial target")
	}
	st, err := LoadState(trial)
	if err != nil {
		return nil, err
	}
	if st.Selection.Empty() {
		st.Selection = home.Selection
		if st.Selection.Empty() {
			st.Selection = Selection{Layers: []LayerName{"core"}}
		}
	}
	if err := e.trialGitBase(trial); err != nil {
		return nil, err
	}
	p := e.BuildPlan(ctx, st, nil, AddOptions{SkipPackages: true, SkipTools: true})
	if err := e.Execute(ctx, p, &st, "shell"); err != nil {
		return nil, err
	}
	var missing []string
	for _, name := range p.Components {
		comp, _ := e.Catalog.Component(name)
		if len(e.missingCommands(comp)) > 0 {
			missing = append(missing, string(name))
		}
	}
	if len(missing) > 0 {
		e.printf("ds shell: missing tools: %s\n", strings.Join(missing, " "))
		e.printf("ds shell: preview installation with: ds add %s --dry-run\n", strings.Join(missing, " "))
	}
	e.printf("ds shell: trial %s; package and tool installs affect the host\n", trial.Root())
	return e.trialEnviron(trial), nil
}

// trialGitBase includes the user's global Git configuration so identity and
// credentials stay available.
func (e *Env) trialGitBase(t TrialTarget) error {
	if _, err := os.Lstat(t.GitConfig()); err == nil {
		return nil
	}
	p := t.Paths()
	base := e.Environ.get("GIT_CONFIG_GLOBAL")
	if base == "" {
		base = filepath.Join(p.Home, ".gitconfig")
		if !exists(base) {
			base = filepath.Join(p.Config, "git", "config")
		}
	}
	content := fmt.Sprintf("[include]\n\tpath = %s\n", gitQuote(base))
	return writeAtomic(t.GitConfig(), []byte(content), 0o644)
}

func gitQuote(s string) string {
	r := strings.NewReplacer(`\`, `\\`, `"`, `\"`, "\n", `\n`)
	return `"` + r.Replace(s) + `"`
}

func (e *Env) trialEnviron(t TrialTarget) envList {
	p := t.Paths()
	return e.Environ.with(
		"DS_TRIAL", t.Root(),
		"ZDOTDIR", t.ZDotDir(),
		"GIT_CONFIG_GLOBAL", t.GitConfig(),
		"NVIM_APPNAME", t.NvimAppName(),
		"MISE_CONFIG_DIR", t.MiseConfigDir(),
		"MISE_DATA_DIR", p.MiseData,
		"PATH", t.Bin()+":"+filepath.Join(p.MiseData, "shims")+":"+e.Environ.get("PATH"),
	)
}
