(import scripts/lib/filesystem)
(import scripts/lib/inventory)
(import scripts/lib/layers)
(import scripts/lib/managed)
(import scripts/lib/mise)

(defn link [source target]
  (unless (managed/same-link? target source)
    (when (os/lstat target)
      (unless (= :link (os/lstat target :mode))
        (error (string "trial path conflict: " target)))
      (os/rm target))
    (filesystem/ensure-parent target)
    (os/link source target true)))

(defn git-quote [value]
  (string "\"" (string/replace-all "\n" "\\n"
                 (string/replace-all "\"" "\\\""
                   (string/replace-all "\\" "\\\\" value))) "\""))

(defn write-config [target contents]
  (unless (and (os/stat target) (= (string (slurp target)) (string contents)))
    (def temporary (string target "." (os/getpid)))
    (spit temporary contents)
    (os/rename temporary target)))

(defn prepare [root base catalog]
  (def environment (mise/environment base root "core"))
  (def home (or (get base "HOME") (error "HOME is required")))
  (def original (or (get base "DS_SHELL_CONFIG_HOME")
                   (get base "XDG_CONFIG_HOME") (string home "/.config")))
  (def state (string (or (get base "XDG_STATE_HOME") (string home "/.local/state")) "/ds/shell"))
  (def config (string state "/config"))
  (filesystem/ensure-parent (string config "/ds/layer"))
  (filesystem/ensure-parent (string state "/zsh/history"))
  # Other applications retain their existing configuration.
  (when (= :directory (os/stat original :mode))
    (each name (os/dir original)
      (unless (find |(= $ name) ["ds" "nvim"])
        (link (string original "/" name) (string config "/" name)))))
  (each name ["shell.zsh" "gitconfig" "gitignore"]
    (link (string root "/src/dotfiles/" name) (string config "/ds/" name)))
  (link (managed/source-root root base "nvim") (string config "/nvim"))
  (link (string root "/ds") (string state "/bin/ds"))
  (link (mise/binary root environment) (string state "/bin/mise"))
  (write-config (string config "/ds/layer") "core\n")
  (def global (or (get base "DS_SHELL_GIT_GLOBAL") (get base "GIT_CONFIG_GLOBAL") ""))
  (def includes (if (= global "")
                  [(string original "/git/config") (string home "/.gitconfig")]
                  [global]))
  (def gitconfig @"")
  (each source (array/concat (array/slice includes) [(string config "/ds/gitconfig")])
    (buffer/push-string gitconfig "[include]\npath = " (git-quote source) "\n"))
  (buffer/push-string gitconfig "[core]\nexcludesFile = "
    (git-quote (string config "/ds/gitignore")) "\n")
  (write-config (string state "/git-base") gitconfig)
  (unless (os/lstat (string state "/gitconfig"))
    (write-config (string state "/gitconfig") "[include]\npath = git-base\n"))
  (def paths @[(string state "/bin")])
  (def installed (inventory/collect catalog root environment))
  (each component (layers/resolve catalog "core" [])
    (each executable (get-in installed [component :executables] [])
      (when executable
        (layers/append-unique paths (string/join (slice (string/split "/" executable) 0 -2) "/")))))
  (put environment "PATH" (string (string/join paths ":") ":" (get base "PATH" "")))
  (put environment "DS_SHELL_PATH" (string/join paths ":"))
  (put environment "DS_SHELL_ROOT" root)
  (put environment "DS_SHELL_CONFIG_HOME" original)
  (put environment "DS_SHELL_GIT_GLOBAL" global)
  (put environment "DS_SHELL_STATE" state)
  (put environment "GIT_CONFIG_GLOBAL" (string state "/gitconfig"))
  (put environment "XDG_CONFIG_HOME" config)
  (put environment "MISE_CONFIG_DIR" (string config "/ds/mise"))
  (put environment "MISE_SYSTEM_CONFIG_DIR" (string config "/ds/mise-system"))
  (put environment "ZDOTDIR" (string root "/src/dotfiles/trial"))
  environment)

(defn start [root base catalog]
  (os/posix-exec ["zsh" "-d" "-i"] :pe (prepare root base catalog)))
