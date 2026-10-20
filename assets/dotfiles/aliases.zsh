_ds_alias_root="${${(%):-%x}:A:h}"
source "$_ds_alias_root/omz/directories.zsh"
source "$_ds_alias_root/omz/clipboard.zsh"
source "$_ds_alias_root/omz/git.zsh"
source "$_ds_alias_root/omz/git.plugin.zsh"
source "$_ds_alias_root/omz/docker.plugin.zsh"
unset _ds_alias_root

alias ..='cd ..'
alias so=source
alias :q=exit
alias wrap='tput smam'
alias nowrap='tput rmam'
if (( $+commands[ouch] )); then
  alias extract='ouch decompress'
elif [[ ${aliases[extract]:-} == 'ouch decompress' ]]; then
  unalias extract
fi

if (( $+commands[xh] )); then
  alias http=xh
  alias https='xh --https'
else
  [[ ${aliases[http]:-} != xh ]] || unalias http
  [[ ${aliases[https]:-} != 'xh --https' ]] || unalias https
fi

if (( $+commands[nvim] )); then
  alias vi=nvim
  alias vim=nvim
else
  [[ ${aliases[vi]:-} != nvim ]] || unalias vi
  [[ ${aliases[vim]:-} != nvim ]] || unalias vim
fi

if (( $+commands[bat] )); then
  alias cat=bat
elif [[ ${aliases[cat]:-} == bat ]]; then
  unalias cat
fi

if (( $+commands[eza] )) && command eza --version >/dev/null 2>&1; then
  alias ls=eza
  alias tree='eza --tree'
else
  [[ ${aliases[ls]:-} != eza ]] || unalias ls
  [[ ${aliases[tree]:-} != 'eza --tree' ]] || unalias tree
fi

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
