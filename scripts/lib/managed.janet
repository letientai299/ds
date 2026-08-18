(import scripts/lib/mise)

(def rc-start "# >>> df managed >>>")
(def rc-end "# <<< df managed <<<")

(defn path [home relative]
  (string home "/" relative))

(defn mkdir-parent [_runner _environment target]
  (def parts (string/split "/" target))
  (var current "")
  (each part (slice parts 0 (- (length parts) 1))
    (unless (empty? part)
      (set current (string current "/" part))
      (os/mkdir current)))
  true)

(defn same-link? [target source]
  (and (= :link (os/lstat target :mode)) (= source (os/readlink target))))

(defn link-state [target source]
  (cond
    (not (os/stat source)) :unavailable
    (same-link? target source) :present
    (os/lstat target) :conflict
    :else :missing))

(defn executable-file? [target]
  (def facts (os/stat target))
  (and facts
       (= :file (get facts :mode))
       (string/find "x" (get facts :permissions))))

(defn command-link-state [target source]
  (cond
    (not (os/stat source)) :unavailable
    (same-link? target source) :present
    (executable-file? target) :present
    (os/lstat target) :conflict
    :else :missing))

(defn text-state [target contents]
  (cond
    (not (os/stat target)) :missing
    (= contents (string (slurp target))) :present
    :else :conflict))

(defn layer-state [target desired]
  (if-not (os/stat target)
    :missing
    (let [actual (string/trim (string (slurp target)))]
      (cond
        (= actual desired) :present
        (and (= desired "core") (= actual "remote")) :present
        (or (= actual "core") (= actual "remote")) :missing
        :else :conflict))))

(defn marker-block [line]
  (string rc-start "\n" line "\n" rc-end "\n"))

(defn marker-state [target line]
  (cond
    (not (os/stat target)) :missing
    (= :link (os/lstat target :mode)) :conflict
    :else
    (let [contents (slurp target)
          block (marker-block line)]
      (cond
        (string/find block contents) :present
        (or (string/find rc-start contents) (string/find rc-end contents)) :conflict
        :else :missing))))

(defn source-root [root environment name]
  (def configured
    (or (get environment (string "DF_" (string/ascii-upper name) "_SOURCE"))
        (let [sibling (string root "/../" name ".conf")
              bundled (string root "/vendor/" name ".conf")]
          (if (os/stat sibling) sibling bundled))))
  (if (os/stat configured) (os/realpath configured) configured))

(defn entries [root environment layer]
  (def home (or (get environment "HOME") (error "HOME is required")))
  (def config-home (or (get environment "XDG_CONFIG_HOME") (path home ".config")))
  (def core
    @[{:kind :link :target (path home ".local/bin/ds") :source (string root "/ds")}
     {:kind :command-link :target (path home ".local/bin/mise") :source (mise/binary root environment)}
     {:kind :link :target (path config-home "df/shell.zsh") :source (string root "/dotfiles/shell.zsh")}
     {:kind :link :target (path config-home "df/gitconfig") :source (string root "/dotfiles/gitconfig")}
     {:kind :link :target (path config-home "df/gitignore") :source (string root "/dotfiles/gitignore")}
     {:kind :link :target (path config-home "df/mise/config.toml") :source (string root "/mise.toml")}
     {:kind :link :target (path config-home "df/mise/config.remote.toml") :source (string root "/mise.remote.toml")}
     {:kind :link :target (path config-home "df/mise/config.starship.toml") :source (string root "/mise.starship.toml")}
     {:kind :layer :target (path config-home "df/layer") :contents layer}
     {:kind :link :target (path config-home "nvim") :source (source-root root environment "NVIM")}
     {:kind :marker :target (path home ".zshrc") :line (string "source \"" config-home "/df/shell.zsh\"")}
     {:kind :marker :target (path home ".gitconfig") :line (string "[include]\n\tpath = " config-home "/df/gitconfig")}])
  (if (= layer "remote")
    (let [tmux-source (source-root root environment "TMUX")]
      (array/concat core
                    @[{:kind :link :target (path config-home "tmux") :source tmux-source}
                     {:kind :link :target (path home ".local/bin/tm") :source (string tmux-source "/tm")}]))
    core))

(defn state [entry]
  (case (get entry :kind)
    :link (link-state (get entry :target) (get entry :source))
    :command-link (command-link-state (get entry :target) (get entry :source))
    :marker (marker-state (get entry :target) (get entry :line))
    :layer (layer-state (get entry :target) (get entry :contents))))

(defn inspect [root environment layer]
  (map (fn [entry] (merge entry {:state (state entry)})) (entries root environment layer)))

(defn conflicts [root environment layer]
  (filter |(= :conflict (get $ :state)) (inspect root environment layer)))

(defn backup-path [entry]
  (string (get entry :target) ".df-adopted"))

(defn prepare [runner root environment layer mode]
  (each entry (conflicts root environment layer)
    (def target (get entry :target))
    (case mode
      :adopt
      (do
        (def backup (backup-path entry))
        (when (os/lstat backup)
          (error (string "adoption backup already exists: " backup)))
        (unless (= 0 (runner ["mv" "--" target backup] environment))
          (error (string "could not adopt: " target))))
      :force
      (unless (= 0 (runner ["rm" "-rf" "--" target] environment))
        (error (string "could not replace: " target)))
      (error (string "unknown takeover mode: " mode)))))

(defn apply-entry [runner environment entry]
  (def target (get entry :target))
  (case (get entry :kind)
    :link
    (unless (= :present (state entry))
      (unless (os/stat (get entry :source))
        (error (string "managed source is unavailable: " (get entry :source))))
      (mkdir-parent runner environment target)
      (os/link (get entry :source) target true))
    :command-link
    (unless (= :present (state entry))
      (unless (os/stat (get entry :source))
        (error (string "managed source is unavailable: " (get entry :source))))
      (mkdir-parent runner environment target)
      (os/link (get entry :source) target true))
    :marker
    (unless (= :present (state entry))
      (mkdir-parent runner environment target)
      (def contents (if (os/stat target) (slurp target) ""))
      (def separator (if (or (empty? contents) (string/has-suffix? "\n" contents)) "" "\n"))
      (spit target (string contents separator (marker-block (get entry :line)))))
    :layer
    (unless (= :present (state entry))
      (mkdir-parent runner environment target)
      (spit target (string (get entry :contents) "\n")))))

(defn apply [runner root environment layer]
  (def blocked (conflicts root environment layer))
  (unless (empty? blocked)
    (error (string "managed-file conflict: " (get (first blocked) :target))))
  (each entry (entries root environment layer)
    (apply-entry runner environment entry))
  (def home (get environment "HOME"))
  (def state-home (or (get environment "XDG_STATE_HOME") (path home ".local/state")))
  (mkdir-parent runner environment (path state-home "zsh/history")))

(defn remove-marker [target line]
  (when (and (os/stat target) (not= :link (os/lstat target :mode)))
    (def contents (slurp target))
    (def block (marker-block line))
    (when (string/find block contents)
      (def remaining (string/replace block "" contents))
      (if (empty? remaining) (os/rm target) (spit target remaining)))))

(defn unapply [runner root environment layer]
  (each entry (reverse (entries root environment layer))
    (case (get entry :kind)
      :link (when (same-link? (get entry :target) (get entry :source))
              (os/rm (get entry :target)))
      :command-link (when (same-link? (get entry :target) (get entry :source))
                      (os/rm (get entry :target)))
      :marker (remove-marker (get entry :target) (get entry :line))
      :layer (when (and (os/stat (get entry :target))
                        (find |(= $ (string/trim (string (slurp (get entry :target))))) ["core" "remote"]))
               (os/rm (get entry :target))))
    (def backup (backup-path entry))
    (when (and (os/lstat backup) (not (os/lstat (get entry :target))))
      (runner ["mv" "--" backup (get entry :target)] environment))))
