(def catalog
  @{:layers
  {:core [:mise :git :curl :zsh :neovim :fd :fzf :ripgrep :nnn :jq :xh]
   :remote [:mise :git :curl :zsh :neovim :fd :fzf :ripgrep :nnn :jq :xh :tmux :docker :zoxide :bat :delta]}
  :optional [:starship]
  :components
  {:bat {:commands ["bat"] :owner :mise}
   :curl {:commands ["curl"] :owner :native}
   :delta {:commands ["delta"] :owner :mise :tool "http-delta"}
   :docker {:commands ["docker"] :owner :native}
   :fd {:commands ["fd"] :owner :mise}
   :fzf {:commands ["fzf"] :owner :mise}
   :git {:commands ["git"] :owner :native}
   :jq {:commands ["jq"] :owner :mise}
   :mise {:commands ["mise"] :owner :runtime}
   :neovim {:commands ["nvim"] :owner :native}
   :nnn {:commands ["nnn"] :owner :native}
   :ripgrep {:commands ["rg"] :owner :mise}
   :starship {:commands ["starship"] :owner :mise}
   :tmux {:commands ["tmux"] :owner :native}
   :xh {:commands ["xh"] :owner :mise}
   :zoxide {:commands ["zoxide"] :owner :mise}
   :zsh {:commands ["zsh"] :owner :native}}})
