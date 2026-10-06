(import scripts/lib/mise)
(import scripts/lib/process)

(def bootstrap-command
  (string "+lua local ok, err = pcall(function() require('lib.bootstrap').run() end); "
          "if not ok then print(err); vim.cmd('cquit 1') end"))

(defn bootstrap [runner root profile environment]
  (def settings (mise/environment environment root profile))
  (put settings "NVIM_APPNAME" "nvim")
  (put settings "GIT_TERMINAL_PROMPT" "0")
  (with [input (file/open "/dev/null" :r)]
    (put settings :in input)
    (def status
      (process/execute runner
        [(mise/binary root settings) "-C" (mise/config-root root) "exec" "--"
         "nvim" "--headless" bootstrap-command "+qa!"] settings))
    (unless (= 0 status)
      (error (string "Neovim bootstrap failed with status " status)))))
