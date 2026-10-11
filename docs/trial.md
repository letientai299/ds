# Trial shell

`ds shell` opens Zsh with ds-managed applications reading configuration from
`<state>/ds/trial`. Use it to try a selection or an asset change without
touching the normal configuration.

- `HOME`, general XDG paths, SSH configuration, and other applications stay
  real.
- `ZDOTDIR`, `GIT_CONFIG_GLOBAL`, `MISE_CONFIG_DIR`, Yazi, and history point
  into the trial. The trial Git configuration includes the user's global one, so
  identity and credentials keep working.
- Neovim uses `NVIM_APPNAME=ds-trial-nvim`, so its configuration link, plugins,
  and state live under that name.
- Tmux runs on its own `ds-trial` server with the trial configuration.
  `tmux.conf` sources `~/.config/tmux/conf.d`, which stays the real directory.

The first `ds shell` copies the normal selection, or `core`, into the trial and
converges trial files without installing packages or tools. Missing tools are
listed. Inside the trial, `ds add` and `ds status` act on the trial selection;
tool and package installations still change the host, and `--dry-run` shows them
first.

Trial state persists across sessions. Delete `<state>/ds/trial` and
`<config>/ds-trial-nvim` to reset it.
