export EDITOR=nvim
if [[ $OSTYPE == darwin* ]]; then
  export LANG=en_US.UTF-8
else
  export LANG=C.UTF-8
fi
export LC_CTYPE="$LANG"
export LC_ALL="$LANG"

export FZF_DEFAULT_COMMAND=fzf-files
export FZF_CTRL_T_COMMAND=fzf-files
export FZF_DEFAULT_OPTS='--height 80% --reverse'
export RIPGREP_CONFIG_PATH="$XDG_CONFIG_HOME/ds/rgrc"
export HISTSIZE=10000000
export SAVEHIST=10000000
