(def catalog
  @{:layers
  {:core [:mise :git :curl :zsh :neovim :fd :fzf :ripgrep :zoxide :jq :xh]
   :remote [:mise :git :curl :zsh :neovim :fd :fzf :ripgrep :zoxide :jq :xh :tmux :docker :yazi]
   :extra [:bat :delta :worktrunk :gokill :eza :gdu :ouch]
   :ui [:kitty]
   :all [:mise :git :curl :zsh :neovim :fd :fzf :ripgrep :zoxide :jq :xh :bat :delta :worktrunk :gokill :eza :gdu :ouch :tmux :docker :yazi :kitty]}
  :profiles {:core [:core] :remote [:core :remote] :extra [:extra] :ui [:ui] :all [:core :extra :remote :ui]}
  :optional []
  :components
  {:bat {:commands ["bat"] :owner :mise :version "latest"}
   :curl {:commands ["curl"] :owner :native}
   :delta {:commands ["delta"] :owner :mise :tool "http-delta" :version "0.18.2"}
   :docker {:commands ["docker"] :owner :native}
   :eza {:commands ["eza"] :owner :mise :version "latest"}
   :fd {:commands ["fd"] :owner :mise :version "latest"}
   :fzf {:commands ["fzf"] :owner :mise :version "latest"}
   :gdu {:commands ["gdu"] :owner :mise :version "latest"}
   :git {:commands ["git"] :owner :native}
   :gokill {:commands ["gokill"] :owner :mise :tool "http-gokill" :version "1.4.1"}
   :jq {:commands ["jq"] :owner :mise :version "latest"}
   :kitty {:commands ["kitty" "kitten"] :owner :mise :tool "http-kitty" :version "0.49.1"}
   :mise {:commands ["mise"] :owner :runtime}
   :neovim {:commands ["nvim"] :owner :mise :version "0.12.5"}
   :ouch {:commands ["ouch"] :owner :mise :tool "http-ouch" :version "0.8.3"}
   :ripgrep {:commands ["rg"] :owner :mise :version "latest"}
   :tmux {:commands ["tmux"] :owner :native}
   :worktrunk {:commands ["wt"] :owner :mise :tool "http-worktrunk" :version "0.79.0"}
   :xh {:commands ["xh"] :owner :mise :version "latest"}
   :yazi {:commands ["yazi" "ya"] :owner :mise :version "latest"}
   :zoxide {:commands ["zoxide"] :owner :mise :version "latest"}
   :zsh {:commands ["zsh"] :owner :native}}})
