(import scripts/lib/managed)

(defn assert= [expected actual message]
  (unless (= expected actual)
    (error (string message ": expected " expected ", got " actual))))

(def home (or (os/getenv "DF_TEST_HOME") (error "DF_TEST_HOME is required")))
(def root (or (os/getenv "DF_ROOT") (error "DF_ROOT is required")))
(def source (string home "/nvim-source"))
(os/mkdir home)
(os/mkdir source)
(spit (string home "/.zshrc") "# user configuration\n")
(def existing-mise (string home "/.local/bin/mise"))

(def environment
  {"HOME" home
   "XDG_CONFIG_HOME" (string home "/config")
   "PATH" (or (os/getenv "PATH") "/usr/bin:/bin")
   "DF_MISE" (or (os/getenv "DF_MISE") (error "DF_MISE is required"))
   "DF_NVIM_SOURCE" source})
(defn runner [_argv _environment] 0)

(managed/mkdir-parent runner environment existing-mise)
(spit existing-mise "existing mise\n")
(os/chmod existing-mise 493)

(managed/apply runner root environment "core")
(managed/apply runner root environment "core")
(assert= 0 (length (filter |(not= :present (get $ :state))
                            (managed/inspect root environment "core")))
         "apply converges all managed targets")
(assert= true (not= nil (string/find "# user configuration" (slurp (string home "/.zshrc"))))
         "apply preserves user rc content")
(assert= "existing mise\n" (string (slurp existing-mise)) "apply preserves existing mise")

(managed/unapply runner root environment "core")
(assert= "# user configuration\n"
         (string (slurp (string home "/.zshrc")))
         "unapply preserves user rc content")
(assert= nil (os/stat (string home "/config/nvim")) "unapply removes owned Neovim link")
(assert= "existing mise\n" (string (slurp existing-mise)) "unapply preserves existing mise")

(def old-zshrc (string home "/old-zshrc"))
(os/rm (string home "/.zshrc"))
(spit old-zshrc "old linked configuration\n")
(os/link old-zshrc (string home "/.zshrc") true)
(assert= :conflict
         (get (first (filter |(= (string home "/.zshrc") (get $ :target))
                             (managed/conflicts root environment "core"))) :state)
         "linked rc is a conflict")

(spit (string home "/config/df/shell.zsh") "user-owned\n")
(assert= :conflict
         (get (first (managed/conflicts root environment "core")) :state)
         "existing dedicated file is a conflict")
(defn real-runner [argv target-environment]
  (os/execute argv :pe target-environment))
(managed/prepare real-runner root environment "core" :adopt)
(managed/apply real-runner root environment "core")
(assert= true
         (not= nil (os/stat (string home "/config/df/shell.zsh.df-adopted")))
         "adoption keeps a backup")
(managed/unapply real-runner root environment "core")
(assert= "user-owned\n"
         (string (slurp (string home "/config/df/shell.zsh")))
         "unapply restores adopted content")
(assert= old-zshrc (os/readlink (string home "/.zshrc")) "unapply restores linked rc")
(assert= "old linked configuration\n" (string (slurp old-zshrc)) "adoption does not edit linked rc")

(print "managed: ok")
