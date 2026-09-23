(import scripts/lib/filesystem)
(import scripts/lib/managed)

(defn assert= [expected actual message]
  (unless (= expected actual)
    (error (string message ": expected " expected ", got " actual))))

# strip-marker-block is what stands between a marker conflict and the user's rc
# file, so every content shape it can meet is covered here rather than through a
# filesystem fixture.
(def strip-cases
  [["plain user file\n" "plain user file\n" "no markers"]
   ["" "" "empty file"]
   [(string managed/rc-start "\nA\n" managed/rc-end "\n") "" "block is the whole file"]
   [(string "top\n" managed/rc-start "\nA\n" managed/rc-end "\nbottom\n") "top\nbottom\n" "block mid file"]
   [(string "user\n" managed/rc-start "\nA\n" managed/rc-end) "user\n" "block without a trailing newline"]
   [(string "user\n" managed/rc-start "\n[include]\n") "user\n[include]\n" "end marker lost to a hand edit"]
   [(string "user\n" managed/rc-start "\nsource x\nSECRET=1\n") "user\nsource x\nSECRET=1\n"
    "content below a lost end marker survives"]
   [(string "user\n" managed/rc-start "\nSECRET\n" managed/rc-start "\nA\n" managed/rc-end "\n")
    "user\nSECRET\n" "lost end marker before a later block"]
   [(string managed/rc-end "\nstray\n" managed/rc-start "\nA\n" managed/rc-end "\n") "stray\n" "orphaned end marker"]
   [(string "user\n" managed/rc-start "\nA\n" managed/rc-end "\n" managed/rc-start "\nB\n" managed/rc-end "\n")
    "user\n" "repeated blocks"]])

(each [contents expected message] strip-cases
  (assert= expected (managed/strip-marker-block contents) (string "strip: " message)))

(def home (or (os/getenv "DS_TEST_HOME") (error "DS_TEST_HOME is required")))
(def root (or (os/getenv "DS_ROOT") (error "DS_ROOT is required")))
(def source (string home "/nvim-source"))
(os/mkdir home)
(os/mkdir source)
(spit (string home "/.zshrc") "# user configuration\n")
(def existing-mise (string home "/.local/bin/mise"))

(def environment
  {"HOME" home
   "XDG_CONFIG_HOME" (string home "/config")
   "PATH" (or (os/getenv "PATH") "/usr/bin:/bin")
   "DS_MISE" (or (os/getenv "DS_MISE") (error "DS_MISE is required"))
   "DS_NVIM_SOURCE" source})
(defn runner [_argv _environment] 0)

(filesystem/ensure-parent existing-mise)
(spit existing-mise "existing mise\n")
(os/chmod existing-mise 493)

(managed/apply root environment "core")
(managed/apply root environment "core")
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

(spit (string home "/config/ds/shell.zsh") "user-owned\n")
(assert= :conflict
         (get (first (managed/conflicts root environment "core")) :state)
         "existing dedicated file is a conflict")
(defn real-runner [argv target-environment]
  (os/execute argv :pe target-environment))
(managed/prepare real-runner root environment "core" :adopt)
(managed/apply root environment "core")
(assert= true
         (not= nil (os/stat (string home "/config/ds/shell.zsh.ds-adopted")))
         "adoption keeps a backup")
(managed/unapply real-runner root environment "core")
(assert= "user-owned\n"
         (string (slurp (string home "/config/ds/shell.zsh")))
         "unapply restores adopted content")
(assert= old-zshrc (os/readlink (string home "/.zshrc")) "unapply restores linked rc")
(assert= "old linked configuration\n" (string (slurp old-zshrc)) "adoption does not edit linked rc")

# A marker conflict must never cost the user the rest of the rc file. Each case
# needs its own home because prepare consumes the conflict it is given.
(defn seeded-home [name]
  (def target (string home "/" name))
  (os/mkdir target)
  (os/mkdir (string target "/nvim-source"))
  target)

(defn marker-environment [marker-home]
  {"HOME" marker-home
   "XDG_CONFIG_HOME" (string marker-home "/config")
   "PATH" (or (os/getenv "PATH") "/usr/bin:/bin")
   "DS_MISE" (or (os/getenv "DS_MISE") (error "DS_MISE is required"))
   "DS_NVIM_SOURCE" (string marker-home "/nvim-source")})

(def user-gitconfig "[user]\n\tname = Real Person\n")

(defn seed-perturbed-marker [marker-home marker-environment]
  (managed/apply root marker-environment "core")
  (def target (string marker-home "/.gitconfig"))
  (spit target (string user-gitconfig (slurp target)))
  # One stray space inside the block is enough to make marker-state report
  # :conflict, which is what used to delete the whole file.
  (spit target (string/replace managed/rc-end (string managed/rc-end " ") (slurp target)))
  (os/chmod target "rw-------")
  target)

(def marker-cases
  [[:force "force strips only the managed block"]
   [:adopt "adopt copies the file and strips only the managed block"]])

(each [mode message] marker-cases
  (def marker-home (seeded-home (string "marker-" mode)))
  (def marker-env (marker-environment marker-home))
  (def target (seed-perturbed-marker marker-home marker-env))
  (assert= :conflict
           (get (first (filter |(= target (get $ :target))
                               (managed/conflicts root marker-env "core"))) :state)
           (string message ": perturbed block is a conflict"))
  (managed/prepare real-runner root marker-env "core" mode)
  (def survived (string (slurp target)))
  (assert= true (not= nil (string/find "name = Real Person" survived))
           (string message ": user content survives"))
  (assert= nil (string/find managed/rc-start survived)
           (string message ": managed block is gone"))
  (assert= (= mode :adopt)
           (not= nil (os/stat (string target ".ds-adopted")))
           (string message ": backup presence"))
  (when (= mode :adopt)
    (assert= "rw-------"
             (os/stat (string target ".ds-adopted") :permissions)
             (string message ": backup keeps the target mode")))
  (managed/apply root marker-env "core")
  (assert= :present
           (get (first (filter |(= target (get $ :target))
                               (managed/inspect root marker-env "core"))) :state)
           (string message ": apply reconverges the block")))

# A block whose end marker was lost must still be strippable, otherwise prepare
# reports success and the following apply fails on the same conflict.
(def truncated-home (seeded-home "marker-truncated"))
(def truncated-env (marker-environment truncated-home))
(managed/apply root truncated-env "core")
(def truncated-target (string truncated-home "/.gitconfig"))
(spit truncated-target (string user-gitconfig managed/rc-start "\n[include]\n"))
(managed/prepare real-runner root truncated-env "core" :force)
(assert= (string user-gitconfig "[include]\n")
         (string (slurp truncated-target))
         "truncated block loses its marker line and nothing else")

(var unknown-mode-failed? false)
(try
  (managed/prepare real-runner root truncated-env "core" :replace)
  ([_err] (set unknown-mode-failed? true)))
(assert= true unknown-mode-failed? "unknown takeover mode is rejected")

# Nothing in the suite installed two different versions before this, which is
# how every managed link came to conflict with itself on upgrade.
(def prefix (string home "/prefix"))
(filesystem/ensure-parent (string prefix "/versions/x"))

(defn version-root [version]
  (def target (string prefix "/versions/" version))
  (each relative ["/ds" "/src/dotfiles/shell.zsh" "/src/dotfiles/gitconfig"
                  "/src/dotfiles/gitignore" "/src/mise/mise.toml"
                  "/src/mise/mise.remote.toml" "/src/mise/mise.starship.toml"]
    (def file (string target relative))
    (filesystem/ensure-parent file)
    (spit file (string version "\n")))
  target)

(def upgrade-home (string home "/upgrade"))
(os/mkdir upgrade-home)
(os/mkdir (string upgrade-home "/nvim-source"))
(def upgrade-environment
  {"HOME" upgrade-home
   "XDG_CONFIG_HOME" (string upgrade-home "/config")
   "PATH" (or (os/getenv "PATH") "/usr/bin:/bin")
   "DS_MISE" (or (os/getenv "DS_MISE") (error "DS_MISE is required"))
   "DS_NVIM_SOURCE" (string upgrade-home "/nvim-source")})

(def root-a (version-root "0.0.1-a"))
(managed/apply root-a upgrade-environment "core")
(assert= 0
         (length (filter |(not= :present (get $ :state))
                         (managed/inspect root-a upgrade-environment "core")))
         "first version converges")
(assert= (string prefix "/current/ds")
         (os/readlink (string upgrade-home "/.local/bin/ds"))
         "managed link points through the stable indirection")
(assert= "versions/0.0.1-a" (os/readlink (string prefix "/current")) "current names the first version")

(def root-b (version-root "0.0.2-b"))
(assert= 0
         (length (managed/conflicts root-b upgrade-environment "core"))
         "a newer version does not conflict with the links of the previous one")
(managed/apply root-b upgrade-environment "core")
(assert= 0
         (length (filter |(not= :present (get $ :state))
                         (managed/inspect root-b upgrade-environment "core")))
         "second version converges")
(assert= "versions/0.0.2-b" (os/readlink (string prefix "/current")) "current follows the upgrade")
(assert= "0.0.2-b\n"
         (string (slurp (string upgrade-home "/.local/bin/ds")))
         "the managed link resolves to the newly applied version")

(print "managed: ok")
