package ds

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestParseCategories(t *testing.T) {
	t.Parallel()
	tests := []struct {
		args, skip []string
		want       string
		err        string
	}{
		{want: "ds,tools,plugins,system"},
		{args: []string{"all"}, want: "ds,tools,plugins,system"},
		{args: []string{"tools"}, want: "tools"},
		{args: []string{"system", "ds"}, want: "ds,system"},
		{skip: []string{"system"}, want: "ds,tools,plugins"},
		{args: []string{"all"}, skip: []string{"system"}, want: "ds,tools,plugins"},
		{args: []string{"system"}, skip: []string{"system"}, err: "cannot both upgrade and skip system"},
		{args: []string{"docker"}, err: "unknown upgrade category"},
		{skip: []string{"all"}, err: "unknown skip category"},
		{args: []string{"tools"}, skip: []string{"system"}, want: "tools"},
	}
	for _, tt := range tests {
		t.Run(strings.Join(tt.args, ",")+"-"+strings.Join(tt.skip, ","), func(t *testing.T) {
			got, err := ParseCategories(tt.args, tt.skip)
			if tt.err != "" {
				if err == nil || !strings.Contains(err.Error(), tt.err) {
					t.Fatalf("err = %v", err)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if FormatCategories(got) != tt.want {
				t.Fatalf("got %s", FormatCategories(got))
			}
		})
	}
}

func git(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	cmd.Env = append(cmd.Environ(), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@example.invalid",
		"GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@example.invalid")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

// cloneWithUpstream creates an origin and a tracking clone.
func cloneWithUpstream(t *testing.T, dir, name string) (origin, clone string) {
	origin = filepath.Join(dir, name+".origin")
	clone = filepath.Join(dir, name)
	mustMkdir(t, origin)
	git(t, origin, "init", "-q", "-b", "main")
	git(t, origin, "config", "receive.denyCurrentBranch", "updateInstead")
	writeFile(t, filepath.Join(origin, "f"), "1\n")
	git(t, origin, "add", "f")
	git(t, origin, "commit", "-qm", "one")
	git(t, dir, "clone", "-q", origin, clone)
	return origin, clone
}

func TestRunCategoriesUsesSelection(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	f.add(ComponentRequest{Components: []ComponentName{"bat"}}, AddOptions{})
	err := f.env.RunCategories(context.Background(), f.state(), []Category{CatTools, CatPlugins, CatSystem}, false)
	if err != nil {
		t.Fatalf("%v\n%s", err, f.err.String())
	}
	upgrades := f.logLines("mise -C / upgrade")
	if len(upgrades) != 1 || !strings.HasSuffix(upgrades[0], "upgrade bat") {
		t.Fatalf("upgrades = %v", upgrades)
	}
	if !strings.Contains(f.err.String(), "plugins skipped") || !strings.Contains(f.err.String(), "system skipped") {
		t.Fatalf("output:\n%s", f.err.String())
	}
}

func TestUpgradePreservesExternalTools(t *testing.T) {
	t.Parallel()
	for _, dryRun := range []bool{false, true} {
		t.Run(fmt.Sprint(dryRun), func(t *testing.T) {
			f := newFixture(t)
			f.add(ComponentRequest{Components: []ComponentName{"claude", "bat"}}, AddOptions{})
			fragment := fragmentPath(f.env.Target)
			content := strings.ReplaceAll(readFile(t, fragment), "claude-code = 'latest'\n", "")
			if content == readFile(t, fragment) {
				t.Fatal("claude request was not removed")
			}
			writeFile(t, fragment, content)
			if err := os.Remove(filepath.Join(f.env.Target.Paths().MiseData, "fake", "claude-code")); err != nil {
				t.Fatal(err)
			}
			writeExec(t, filepath.Join(f.tools, "claude"), fakeCommand)
			st := f.state()
			if p := f.env.BuildPlan(context.Background(), st, nil, AddOptions{}); len(p.Blockers) == 0 {
				t.Fatal("add lost conflict protection")
			}
			before := snapshot(t, f.home)
			p := f.env.BuildPlan(context.Background(), st, nil, AddOptions{KeepConflicts: true})
			if len(p.Blockers) > 0 || hasAction(p, "install mise tools") || len(p.Notes) == 0 {
				t.Fatalf("upgrade plan: %+v; %v", p, actionNames(p))
			}
			if !dryRun {
				if err := f.env.Execute(context.Background(), p, &st, "upgrade"); err != nil {
					t.Fatal(err)
				}
			}
			if err := f.env.RunCategories(context.Background(), st, []Category{CatTools, CatPlugins}, dryRun); err != nil {
				t.Fatal(err)
			}
			if readFile(t, fragment) != content {
				t.Fatal("upgrade replaced edited fragment")
			}
			upgrades := f.logLines("mise -C / upgrade")
			if dryRun {
				if len(upgrades) != 0 || !reflect.DeepEqual(before, snapshot(t, f.home)) {
					t.Fatal("dry run changed target")
				}
				if !strings.Contains(f.err.String(), "would run mise upgrade jq bat") {
					t.Fatal(f.err.String())
				}
			} else if len(upgrades) != 1 || !strings.HasSuffix(upgrades[0], "upgrade jq bat") {
				t.Fatalf("upgrades: %v", upgrades)
			}
			r := f.env.Status(context.Background(), st, nil)
			if r.Summary != SummaryConflict {
				t.Fatalf("conflict disappeared: %+v", r)
			}
			for _, c := range r.Components {
				if c.Name == "claude" && (c.State != compInstalled || c.Detail != externalToolDetail) {
					t.Fatalf("native claude: %+v", c)
				}
			}
		})
	}
}

func TestUpgradeCatalogDownloads(t *testing.T) {
	t.Parallel()
	for _, dryRun := range []bool{false, true} {
		t.Run(fmt.Sprint(dryRun), func(t *testing.T) {
			f := newFixture(t)
			f.add(ComponentRequest{Components: []ComponentName{"delta", "kitty", "ouch", "worktrunk", "bat"}}, AddOptions{})
			if err := f.env.upgradeTools(context.Background(), []ComponentName{"delta", "kitty", "ouch", "worktrunk", "bat"}, dryRun); err != nil {
				t.Fatal(err)
			}
			if !strings.Contains(f.err.String(), "http:kitty pinned to ") {
				t.Fatal(f.err.String())
			}
			want := "upgrade aqua:dandavison/delta aqua:ouch-org/ouch aqua:max-sixty/worktrunk bat"
			upgrades := f.logLines("mise -C / upgrade")
			if dryRun {
				if len(upgrades) != 0 || !strings.Contains(f.err.String(), "would run mise "+want) {
					t.Fatalf("upgrades: %v; output: %s", upgrades, f.err.String())
				}
			} else if len(upgrades) != 1 || !strings.HasSuffix(upgrades[0], want) {
				t.Fatalf("upgrades: %v", upgrades)
			}
		})
	}
}

func TestUpgradeFloatingRequests(t *testing.T) {
	t.Parallel()
	for _, source := range []string{"managed", "override"} {
		for _, dryRun := range []bool{false, true} {
			t.Run(fmt.Sprintf("%s/%t", source, dryRun), func(t *testing.T) {
				f := newFixture(t)
				f.add(ComponentRequest{Components: []ComponentName{"neovim"}}, AddOptions{})
				script := strings.ReplaceAll(fakeMise, `"requested_version":"latest"`, `"requested_version":"0.12.5"`)
				script = strings.ReplaceAll(script, "upgrade | bootstrap | exec)", "use | upgrade | bootstrap | exec)")
				if source == "override" {
					script = strings.ReplaceAll(script, "conf.d/10-ds.toml", "config.toml")
				}
				writeExec(t, filepath.Join(f.tools, "mise"), script)
				before := snapshot(t, f.home)
				if err := f.env.upgradeTools(context.Background(), []ComponentName{"neovim"}, dryRun); err != nil {
					t.Fatal(err)
				}
				upgrades := f.logLines("mise -C / upgrade")
				uses := f.logLines("mise -C / use")
				if dryRun {
					if len(upgrades) != 0 || len(uses) != 0 || !reflect.DeepEqual(before, snapshot(t, f.home)) {
						t.Fatal("dry run changed target")
					}
					if strings.Contains(f.err.String(), "use --fuzzy --path ") != (source == "managed") {
						t.Fatal(f.err.String())
					}
					return
				}
				var wantUses []string
				if source == "managed" {
					wantUses = []string{"mise -C / use --fuzzy --path " + fragmentPath(f.env.Target) + " neovim@latest"}
				}
				if !reflect.DeepEqual(uses, wantUses) || !reflect.DeepEqual(upgrades, []string{"mise -C / upgrade neovim"}) {
					t.Fatalf("uses = %v; want %v; upgrades = %v", uses, wantUses, upgrades)
				}
			})
		}
	}
}
