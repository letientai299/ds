(def catalog
  @{:layers
  {:core [:mise :git :curl :zsh :neovim :fd :fzf :ripgrep :worktrunk :zoxide :jq :gokill :xh]
   :remote [:mise :git :curl :zsh :neovim :fd :fzf :ripgrep :worktrunk :zoxide :jq :gokill :xh :tmux :docker :bat :delta]}
  :optional []
  :components
  {:bat {:commands ["bat"] :owner :mise :version "0.25.0"}
   :curl {:commands ["curl"] :owner :native}
   :delta {:commands ["delta"] :owner :mise :tool "http-delta" :version "0.18.2"}
   :docker {:commands ["docker"] :owner :native}
   :fd {:commands ["fd"] :owner :mise :version "10.4.2"}
   :fzf {:commands ["fzf"] :owner :mise :version "0.74.2"}
   :git {:commands ["git"] :owner :native}
   :gokill {:commands ["gokill"] :owner :mise :tool "http-gokill" :version "1.4.1"}
   :jq {:commands ["jq"] :owner :mise :version "1.8.2"}
   :mise {:commands ["mise"] :owner :runtime}
   :neovim {:commands ["nvim"] :owner :mise :version "0.12.5"}
   :ripgrep {:commands ["rg"] :owner :mise :version "15.2.0"}
   :tmux {:commands ["tmux"] :owner :native}
   :worktrunk {:commands ["wt"] :owner :mise :tool "http-worktrunk" :version "0.79.0"}
   :xh {:commands ["xh"] :owner :mise :version "0.26.2"}
   :zoxide {:commands ["zoxide"] :owner :mise :version "0.9.8"}
   :zsh {:commands ["zsh"] :owner :native}}})
