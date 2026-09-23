(import scripts/lib/filesystem)
(import scripts/lib/mise)

(def rc-start "# >>> ds managed >>>")
(def rc-end "# <<< ds managed <<<")

(defn path [home relative]
  (string home "/" relative))

(defn parent-directory [path]
  (def index (last (string/find-all "/" path)))
  (if (and index (> index 0)) (slice path 0 index) path))

(defn basename [path]
  (last (string/split "/" path)))

# A version directory is immutable and its name changes with every release, so
# a link built from it conflicts with itself the next time a version lands.
# A delivered install therefore links through a stable `<prefix>/current`
# indirection; a checkout has no versions/ layout and keeps using its own root.
(defn delivered? [root]
  (= "versions" (basename (parent-directory root))))

(defn link-root [root]
  (if (delivered? root)
    (string (parent-directory (parent-directory root)) "/current")
    root))

(defn point-current [root]
  (when (delivered? root)
    (def link (link-root root))
    (when (os/lstat link) (os/rm link))
    # Relative, so the whole prefix stays relocatable.
    (os/link (string "versions/" (basename root)) link true)))

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

(defn first-marker [contents]
  (def start (string/find rc-start contents))
  (def end (string/find rc-end contents))
  (cond
    (nil? start) end
    (nil? end) start
    (min start end)))

# Removes every managed region, tolerating a block whose end marker was lost to
# a hand edit, an orphaned end marker, and repeated blocks. Anything left behind
# keeps marker-state at :conflict, so apply would fail right after prepare
# reported success.
(defn strip-marker-block [contents]
  (var remaining contents)
  (var from (first-marker remaining))
  (while from
    (def found (string/find rc-end remaining from))
    (def next-start (string/find rc-start remaining (+ from 1)))
    # A start marker whose end marker was lost must consume its own line and no
    # more. Everything below it is user content, and force keeps no backup.
    (def stop
      (if (and found (or (nil? next-start) (< found next-start)))
        (+ found (length rc-end))
        (or (string/find "\n" remaining from) (length remaining))))
    (def tail (slice remaining stop))
    (set remaining
         (string (slice remaining 0 from)
                 (if (string/has-prefix? "\n" tail) (slice tail 1) tail)))
    (set from (first-marker remaining)))
  remaining)

(defn source-root [root environment name]
  (def configured (get environment (string "DS_" (string/ascii-upper name) "_SOURCE")))
  (cond
    configured (if (os/stat configured) (os/realpath configured) configured)
    # A checkout keeps its sibling checkouts resolved to a concrete path.
    (os/stat (string root "/../" name ".conf")) (os/realpath (string root "/../" name ".conf"))
    # The bundled copy stays expressed through `root`, which is already stable.
    (string root "/src/vendor/" name ".conf")))

(defn entries [root environment layer]
  (def home (or (get environment "HOME") (error "HOME is required")))
  (def config-home (or (get environment "XDG_CONFIG_HOME") (path home ".config")))
  (def base (link-root root))
  (def core
    @[{:kind :link :target (path home ".local/bin/ds") :source (string base "/ds")}
     {:kind :command-link :target (path home ".local/bin/mise") :source (mise/binary base environment)}
     {:kind :link :target (path config-home "ds/shell.zsh") :source (string base "/src/dotfiles/shell.zsh")}
     {:kind :link :target (path config-home "ds/gitconfig") :source (string base "/src/dotfiles/gitconfig")}
     {:kind :link :target (path config-home "ds/gitignore") :source (string base "/src/dotfiles/gitignore")}
     {:kind :link :target (path config-home "ds/mise/config.toml") :source (string base "/src/mise/mise.toml")}
     {:kind :link :target (path config-home "ds/mise/config.remote.toml") :source (string base "/src/mise/mise.remote.toml")}
     {:kind :link :target (path config-home "ds/mise/config.starship.toml") :source (string base "/src/mise/mise.starship.toml")}
     {:kind :layer :target (path config-home "ds/layer") :contents layer}
     {:kind :link :target (path config-home "nvim") :source (source-root base environment "nvim")}
     {:kind :marker :target (path home ".zshrc") :line (string "source \"" config-home "/ds/shell.zsh\"")}
     {:kind :marker :target (path home ".gitconfig") :line (string "[include]\n\tpath = " config-home "/ds/gitconfig")}])
  (if (= layer "remote")
    (let [tmux-source (source-root base environment "tmux")]
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
  (string (get entry :target) ".ds-adopted"))

# A marker target is a user-owned rc file that ds only ever appends a block to,
# so a takeover must remove the block and nothing else. Moving or deleting the
# whole file would discard everything the user wrote around it.
(defn takeover-marker [entry mode]
  (def target (get entry :target))
  (def contents (string (slurp target)))
  (when (= mode :adopt)
    (def backup (backup-path entry))
    (when (os/lstat backup)
      (error (string "adoption backup already exists: " backup)))
    (spit backup contents)
    (os/chmod backup (os/stat target :permissions)))
  (def remaining (strip-marker-block contents))
  (if (empty? remaining)
    (os/rm target)
    (spit target remaining)))

(defn marker-file? [entry]
  (and (= :marker (get entry :kind))
       (not= :link (os/lstat (get entry :target) :mode))))

(defn prepare [runner root environment layer mode]
  (unless (or (= mode :adopt) (= mode :force))
    (error (string "unknown takeover mode: " mode)))
  (each entry (conflicts root environment layer)
    (def target (get entry :target))
    (cond
      (marker-file? entry) (takeover-marker entry mode)

      (= mode :adopt)
      (do
        (def backup (backup-path entry))
        (when (os/lstat backup)
          (error (string "adoption backup already exists: " backup)))
        (unless (= 0 (runner ["mv" "--" target backup] environment))
          (error (string "could not adopt: " target))))

      (unless (= 0 (runner ["rm" "-rf" "--" target] environment))
        (error (string "could not replace: " target))))))

(defn link-kind? [kind]
  (or (= :link kind) (= :command-link kind)))

(defn apply-entry [entry]
  (def target (get entry :target))
  (when (= :present (state entry)) (break))
  (def kind (get entry :kind))
  (cond
    (link-kind? kind)
    (do
      (unless (os/stat (get entry :source))
        (error (string "managed source is unavailable: " (get entry :source))))
      (filesystem/ensure-parent target)
      (os/link (get entry :source) target true))

    (= :marker kind)
    (do
      (filesystem/ensure-parent target)
      (def contents (if (os/stat target) (slurp target) ""))
      (def separator (if (or (empty? contents) (string/has-suffix? "\n" contents)) "" "\n"))
      (spit target (string contents separator (marker-block (get entry :line)))))

    (= :layer kind)
    (do
      (filesystem/ensure-parent target)
      (spit target (string (get entry :contents) "\n")))))

(defn apply [root environment layer]
  (point-current root)
  (def blocked (conflicts root environment layer))
  (unless (empty? blocked)
    (error (string "managed-file conflict: " (get (first blocked) :target))))
  (each entry (entries root environment layer)
    (apply-entry entry))
  (def home (get environment "HOME"))
  (def state-home (or (get environment "XDG_STATE_HOME") (path home ".local/state")))
  (filesystem/ensure-parent (path state-home "zsh/history")))

(defn remove-marker [target line]
  (when (and (os/stat target) (not= :link (os/lstat target :mode)))
    (def contents (slurp target))
    (def block (marker-block line))
    (when (string/find block contents)
      (def remaining (string/replace block "" contents))
      (if (empty? remaining) (os/rm target) (spit target remaining)))))

(defn release-link [entry]
  (when (same-link? (get entry :target) (get entry :source))
    (os/rm (get entry :target))))

(defn unapply [runner root environment layer]
  (each entry (reverse (entries root environment layer))
    (case (get entry :kind)
      :link (release-link entry)
      :command-link (release-link entry)
      :marker (remove-marker (get entry :target) (get entry :line))
      :layer (when (and (os/stat (get entry :target))
                        (find |(= $ (string/trim (string (slurp (get entry :target))))) ["core" "remote"]))
               (os/rm (get entry :target))))
    (def backup (backup-path entry))
    (when (and (os/lstat backup) (not (os/lstat (get entry :target))))
      (runner ["mv" "--" backup (get entry :target)] environment))))
