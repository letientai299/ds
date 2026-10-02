(import scripts/lib/mise)
(import scripts/lib/platform)
(import scripts/lib/process)

(defn native-commands [environment present?]
  (when (= :linux (platform/normalize-os (get environment "DS_OS")))
    (cond
      (present? "apt-get") [["apt-get" "update"]
                           ["apt-get" "upgrade" "-y" "-o" "Dpkg::Options::=--force-confdef"
                            "-o" "Dpkg::Options::=--force-confold"]]
      (present? "dnf") [["dnf" "upgrade" "-y"]]
      (present? "yum") [["yum" "update" "-y"]]
      (present? "apk") [["apk" "update"] ["apk" "upgrade"]])))

(def neovim-command
  (string "+lua local ok, err = pcall(function() "
          "local loaded, lazy = pcall(require, 'lazy'); "
          "if not loaded then print('ds upgrade: Neovim plugins skipped'); return end; "
          "lazy.update({wait=true, show=false}); "
          "for _, plugin in pairs(require('lazy.core.config').plugins) do "
          "for _, task in ipairs(plugin._.tasks or {}) do "
          "if task:has_errors() then error('Neovim plugin upgrade failed') end "
          "end end end); if not ok then print(err); vim.cmd('cquit 1') end"))

(defn run-command [argv runner environment]
  (with [input (file/open "/dev/null" :r)]
    (process/execute runner argv (merge environment {:in input}))))

(defn run-stage [name commands runner environment emit]
  (if (empty? commands)
    (do (emit (string "ds upgrade: " name " skipped")) 0)
    (try
      (do
        (emit (string "ds upgrade: " name))
        (var result 0)
        (each argv commands
          (def status (run-command argv runner environment))
          (unless (= status 0)
            (emit (string "ds upgrade: " name " failed (" status ")"))
            (set result status)
            (break)))
        (when (= result 0) (emit (string "ds upgrade: " name " succeeded")))
        result)
      ([err] (emit (string "ds upgrade: " name " failed: " err)) 1))))

(defn run [root base-environment present? runner emit]
  (def environment (mise/copy-environment base-environment))
  (put environment "DEBIAN_FRONTEND" "noninteractive")
  (put environment "NEEDRESTART_MODE" "a")
  (put environment "GIT_TERMINAL_PROMPT" "0")
  (var failed? false)
  (def source-status
    (run-stage "configuration repos" [["sh" (string root "/src/scripts/pull-configs.sh")]]
               runner environment emit))
  (unless (= source-status 0) (break source-status))
  (defn stage [name commands settings]
    (def status (run-stage name commands runner settings emit))
    (when (find |(= status $) [130 143]) (os/exit status))
    (unless (= status 0) (set failed? true)))
  (def packages (or (native-commands environment present?) []))
  (def privileged
    (if (= "0" (get environment "DS_UID")) packages
      (map |(tuple "sudo" "-n" "env" "DEBIAN_FRONTEND=noninteractive" "NEEDRESTART_MODE=a" ;$)
           packages)))
  (stage "system packages" privileged environment)
  (def brew-environment (mise/copy-environment environment))
  (put brew-environment "NONINTERACTIVE" "1")
  (put brew-environment "HOMEBREW_NO_ASK" "1")
  (stage "Homebrew" (if (present? "brew") [["brew" "update"] ["brew" "upgrade" "--no-ask"]] [])
         brew-environment)
  (def configured (mise/global-environment environment root))
  (def binary (mise/binary root configured))
  (stage "mise plugins" [[binary "-C" "/" "plugins" "update" "--yes"]] configured)
  (stage "mise tools" [[binary "-C" "/" "upgrade" "--bump" "--no-prune" "--yes"]] configured)
  (stage "Neovim plugins"
         (if (present? "nvim")
           [["nvim" "--headless" neovim-command "+qa"]] []) environment)
  (if failed? 1 0))
