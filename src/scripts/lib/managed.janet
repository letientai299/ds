(import scripts/lib/filesystem)
(import scripts/lib/activation)
(import scripts/lib/mise)
(import scripts/lib/layers)
(import scripts/generated/layers :as generated)

(def rc-start "# >>> ds managed >>>")
(def rc-end "# <<< ds managed <<<")
(def tool-names ["serve" "fzf-files" "fzf-dirs"])

(defn path [home relative]
  (string home "/" relative))

(defn link-root [root]
  (def base (activation/prefix root))
  (if base (string base "/current") root))

(defn same-link? [target source]
  (and (= :link (os/lstat target :mode)) (= source (os/readlink target))))

(defn executable-file? [target]
  (def facts (os/stat target))
  (and facts
       (= :file (get facts :mode))
       (string/find "x" (get facts :permissions))))

(defn layer-state [target desired]
  (cond
    (not (os/lstat target)) :missing
    (not= :file (os/lstat target :mode)) :conflict
    :else
    (let [actual (string/trim (string (slurp target)))]
      (cond
        (= actual desired) :present
        (all |(layers/known-layer? generated/catalog $) (string/split "," actual))
        (if (all (fn [component] (layers/includes? generated/catalog actual component))
                 (layers/layer-components generated/catalog desired)) :present :missing)
        :else :conflict))))

(defn marker-block [line]
  (string rc-start "\n" line "\n" rc-end "\n"))

(defn marker-state [target line]
  (cond
    (not (os/lstat target)) :missing
    (not= :file (os/lstat target :mode)) :conflict
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
  (def shell-state (get environment "DS_SHELL_STATE"))
  (def bin (if shell-state (path shell-state "bin") (path home ".local/bin")))
  (def zshrc (if shell-state (path shell-state "zsh/.zshrc") (path home ".zshrc")))
  (def gitconfig (if shell-state (path shell-state "gitconfig") (path home ".gitconfig")))
  (def ssh-config (path home ".ssh/config"))
  (def base (if shell-state root (link-root root)))
  (def core
    @[{:kind :link :target (path bin "ds") :source (string base "/ds")}
      {:kind :command-link :target (path bin "mise") :source (mise/binary base environment)}
      {:kind :layer :target (path config-home "ds/layer") :contents layer}
      {:kind :link :target (path config-home "ds/mise/config.toml") :source (string base "/src/mise/mise.toml")}])
  (each name (sort (keys (get generated/catalog :layers)))
    (unless (= name :all)
      (array/push core {:kind :link :target (path config-home (string "ds/mise/config." name ".toml"))
                        :source (string base "/src/mise/mise." name ".toml")})))
  (when (layers/includes? generated/catalog layer :zsh)
    (array/concat core
      @[{:kind :link :target (path config-home "ds/shell.zsh") :source (string base "/src/dotfiles/shell.zsh")}
        {:kind :link :target (path config-home "ds/gitconfig") :source (string base "/src/dotfiles/gitconfig")}
        {:kind :link :target (path config-home "ds/gitignore") :source (string base "/src/dotfiles/gitignore")}
        {:kind :link :target (path config-home "ds/ssh_config") :source (string base "/src/dotfiles/ssh_config")}
        {:kind :link :target (path config-home "ds/rgrc") :source (string base "/src/dotfiles/rgrc")}
        {:kind :link :target (path config-home "nvim") :source (source-root base environment "nvim")}
        {:kind :marker :target zshrc :line (string "source \"" config-home "/ds/shell.zsh\"")}
        {:kind :marker :target ssh-config :line (string "Include \"" config-home "/ds/ssh_config\"")}
        {:kind :marker :target gitconfig
         :line (string "[include]\n\tpath = " config-home "/ds/gitconfig"
                        (if shell-state (string "\n[core]\n\texcludesFile = " config-home "/ds/gitignore") ""))}])
    (each name tool-names
      (array/push core {:kind :link :target (path bin name) :source (string base "/src/tools/" name)})))
  (when (layers/includes? generated/catalog layer :tmux)
    (def tmux-source (source-root base environment "tmux"))
    (array/concat core
      @[{:kind :link :target (path config-home "tmux") :source tmux-source}
        {:kind :link :target (path bin "tm") :source (string tmux-source "/tm")}]))
  (when (layers/includes? generated/catalog layer :yazi)
    (array/push core
      {:kind :link :target (path config-home "ds/yazi")
       :source (string base "/src/dotfiles/yazi")}))
  (when (layers/includes? generated/catalog layer :kitty)
    (def kitty-source (source-root base environment "kitty"))
    (array/push core
      {:kind :link :target (path config-home "ds/kitty") :source kitty-source}
      {:kind :link :target (path config-home "ds/kt") :source (string kitty-source "/bin/kt")}
      {:kind :link :target (path bin "kt") :source (string base "/src/tools/kt")}))
  (map (fn [entry]
         (def source (get entry :source))
         (if (and source (string/has-prefix? (string base "/") source))
           (merge entry {:resolved-source (string root (slice source (length base)))})
           entry)) core))

(defn state [entry]
  (case (get entry :kind)
    :link (if (os/stat (or (get entry :resolved-source) (get entry :source)))
            (cond (same-link? (get entry :target) (get entry :source)) :present
                  (os/lstat (get entry :target)) :conflict :else :missing)
            :unavailable)
    :command-link (if (or (same-link? (get entry :target) (get entry :source))
                          (executable-file? (get entry :target))) :present
                    (if (os/stat (or (get entry :resolved-source) (get entry :source)))
                      (if (os/lstat (get entry :target)) :conflict :missing) :unavailable))
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
       (= :file (os/lstat (get entry :target) :mode))))

(defn prepare-entry [runner environment entry mode]
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
      (error (string "could not replace: " target)))))

(defn link-kind? [kind]
  (or (= :link kind) (= :command-link kind)))

(defn apply-entry [entry]
  (def target (get entry :target))
  (when (and (not= :layer (get entry :kind)) (= :present (state entry))) (break))
  (def kind (get entry :kind))
  (cond
    (link-kind? kind)
    (do
      (unless (os/stat (or (get entry :resolved-source) (get entry :source)))
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
      (def temporary (string target "." (os/getpid)))
      (spit temporary (string (get entry :contents) "\n"))
      (os/rename temporary target))))

(defn remove-marker [target line]
  (when (= :file (os/lstat target :mode))
    (def contents (slurp target))
    (def block (marker-block line))
    (when (string/find block contents)
      (def remaining (string/replace block "" contents))
      (if (empty? remaining) (os/rm target) (spit target remaining)))))

(defn release-link [entry]
  (when (same-link? (get entry :target) (get entry :source))
    (os/rm (get entry :target))))
