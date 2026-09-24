_ds_alias_root="${${(%):-%x}:A:h}"
source "$_ds_alias_root/omz/directories.zsh"
source "$_ds_alias_root/omz/clipboard.zsh"
source "$_ds_alias_root/omz/git.zsh"
source "$_ds_alias_root/omz/git.plugin.zsh"
source "$_ds_alias_root/omz/docker.plugin.zsh"
unset _ds_alias_root

alias ..='cd ..'

alias gcf!="git commit --amend --no-edit"
alias gll='git log --pretty="%C(Yellow)%h  %C(reset)%ad (%C(Green)%cr%C(reset))%x09 %C(Cyan)%an: %C(reset)%s"'
alias gwho="git config --list | grep user"
alias gs='git status'
alias gon='git open'
alias cm="git add . && git commit -v"
alias gdo='git diff origin/HEAD..HEAD'

alias dk='docker'
alias dc='docker-compose'
alias dp='docker pull'
alias dcp='docker pull'
