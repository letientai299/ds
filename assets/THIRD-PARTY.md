# Third-party notices

Main builds embed this file with the assets below. ds downloads mise and the
tools it installs from their upstreams, and clones `nvim.conf`, `tmux.conf`, and
`kitty.conf`; they remain under their own licenses.

## Oh My Zsh

`dotfiles/omz` contains shell code from the Oh My Zsh checkout used by the old
dotfiles configuration, at commit `74965c96098134b192f00084f966b4b02438a739`.
Its MIT [license][omz-license] ships beside the code in every main build.

The port includes the Git plugin, its current-branch and clipboard helpers,
directory shortcuts, and Docker aliases. Completion bindings are conditional on
`compdef` being available. Docker completion generation and Git prompt hooks are
omitted so the aliases work without Oh My Zsh startup or cache directories.
Personal overrides live in [`aliases.zsh`][aliases].

## Interactive Zsh plugins

`dotfiles/plugins` contains the runtime sources from the old dotfiles' plugin
checkouts. Each plugin's `REVISION` records its upstream commit. Sources and
licenses travel together in every main build:

- `zsh-defer`: GPL-3.0, see its `LICENSE`.
- `zsh-autosuggestions`: MIT, see its `LICENSE`.
- `zsh-completions`: Zsh license, see its `LICENSE`.
- `fzf-tab`: MIT, see its `LICENSE` and `lib/zsh-ls-colors/LICENSE`.
- `zsh-syntax-highlighting`: BSD-3-Clause, see its `COPYING.md`.

[`interactive.zsh`][interactive] loads completion and these plugins after the
first prompt, in dependency order. Shell startup needs no plugin downloads.

[omz-license]: dotfiles/omz/LICENSE.txt
[aliases]: dotfiles/aliases.zsh
[interactive]: dotfiles/interactive.zsh
