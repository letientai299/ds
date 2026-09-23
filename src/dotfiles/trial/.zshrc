source "$DS_SHELL_ROOT/src/dotfiles/shell.zsh"
export PATH="$DS_SHELL_PATH:$PATH"
HISTFILE="$DS_SHELL_STATE/zsh/history"
autoload -Uz compinit
compinit -d "$DS_SHELL_STATE/zsh/zcompdump"
source <("$DS_DS" completion zsh)
