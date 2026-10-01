(import scripts/lib/platform)
(import scripts/lib/layers)
(import scripts/generated/layers :as generated)
(import scripts/lib/process)
(import scripts/lib/tool-config)
(import scripts/lib/selection)

(defn copy-environment [source]
  (def target @{})
  (eachp [key value] source
    (put target key value))
  target)

(defn env-path [environment key fallback]
  (or (get environment key) fallback))

# The payload mise profiles live beside each other so MISE_ENV can select
# mise.remote.toml next to mise.toml.
(defn config-root [root]
  (string root "/src/mise"))

(defn global-file [environment]
  (or (get environment "MISE_GLOBAL_CONFIG_FILE")
      (string (or (get environment "MISE_CONFIG_DIR")
                  (string (or (get environment "XDG_CONFIG_HOME")
                              (string (get environment "HOME") "/.config")) "/mise"))
              "/config.toml")))

(defn environment [base root layer]
  (def result (copy-environment base))
  (def home (or (get result "HOME") (error "HOME is required")))
  (def config-home (env-path result "XDG_CONFIG_HOME" (string home "/.config")))
  (def data-home (env-path result "XDG_DATA_HOME" (string home "/.local/share")))
  (def state-home (env-path result "XDG_STATE_HOME" (string home "/.local/state")))
  (def cache-home (env-path result "XDG_CACHE_HOME" (string home "/.cache")))
  (put result "MISE_CACHE_DIR" (env-path result "MISE_CACHE_DIR" (string cache-home "/mise")))
  (put result "MISE_CONFIG_DIR" (env-path result "MISE_CONFIG_DIR" (string config-home "/mise")))
  (put result "MISE_DATA_DIR" (env-path result "MISE_DATA_DIR" (string data-home "/mise")))
  (put result "MISE_STATE_DIR" (env-path result "MISE_STATE_DIR" (string state-home "/mise")))
  (put result "MISE_SYSTEM_CONFIG_DIR" (string config-home "/ds/mise-system"))
  # Keep staged applies off old config hooks.
  (put result "MISE_GLOBAL_CONFIG_FILE" (string (config-root root) "/mise.toml"))
  (put result "MISE_OVERRIDE_CONFIG_FILENAMES" "mise.toml")
  (put result "MISE_GLOBAL_CONFIG_ROOT" (config-root root))
  (put result "MISE_TRUSTED_CONFIG_PATHS" (config-root root))
  (put result "MISE_YES" "1")
  (put result "AUBE_ALLOWED_UNPOPULAR_PACKAGES" "git-open")
  (put result "MISE_ENV" (string/join (layers/profiles generated/catalog layer) ","))
  result)

(defn binary [root settings]
  (or
    (get settings "DS_MISE")
    (let [target (platform/runtime-platform
                   {:os (platform/normalize-os (get settings "DS_OS"))
                    :arch (platform/normalize-arch (get settings "DS_ARCH"))})
          bundled (string root "/src/runtime/bin/" target "/mise")
          checkout (string root "/dist/runtime/bin/" target "/mise")]
      (if (os/stat bundled)
        bundled
        (if (os/stat checkout) checkout bundled)))))

(defn bootstrap-argv [mise root dry-run?]
  (def argv @[mise "-C" (config-root root) "bootstrap" "--yes" "--only" "packages"])
  (when dry-run?
    (array/push argv "--dry-run"))
  argv)

(defn owned-profile? [file]
  (when (= :link (os/lstat file :mode))
    (def name (last (string/split "/" file)))
    (def suffix
      (if (find |(= $ name) ["config.toml" "config.ds.toml"])
        "/src/mise/mise.toml"
        (when (and (string/has-prefix? "config." name) (string/has-suffix? ".toml" name))
          (def profile (slice name 7 -6))
          (when (has-key? (get generated/catalog :layers) (keyword profile))
            (string "/src/mise/mise." profile ".toml")))))
    (and suffix (string/has-suffix? suffix (os/readlink file)))))

(defn retire-profiles [directory]
  (when (= :directory (os/stat directory :mode))
    (each name (os/dir directory)
      (def target (string directory "/" name))
      (when (and (not= name "config.toml") (owned-profile? target))
        (os/rm target)))))

(defn global-fragments [settings]
  (def directory (get settings "MISE_CONFIG_DIR"))
  (def files @[])
  (each profile (string/split "," (get settings "MISE_ENV" ""))
    (unless (empty? profile)
      (def file (string directory "/config." profile ".toml"))
      (when (and (os/stat file) (not (owned-profile? file)))
        (array/push files file))))
  (def fragments (string directory "/conf.d"))
  (when (= :directory (os/stat fragments :mode))
    (each name (sort (os/dir fragments))
      (when (string/has-suffix? ".toml" name)
        (array/push files (string fragments "/" name)))))
  files)

(defn global-environment [base root]
  (def result (environment base root "core"))
  (put result "MISE_GLOBAL_CONFIG_FILE" (global-file base))
  (put result "MISE_GLOBAL_CONFIG_ROOT" nil)
  (put result "MISE_ENV" (get base "MISE_ENV" ""))
  result)

(defn apply-profile [runner root layer base-environment dry-run?]
  (def target-environment (environment base-environment root layer))
  (def mise (binary root target-environment))
  (def status (process/execute runner (bootstrap-argv mise root dry-run?) target-environment))
  (when (or dry-run? (not= 0 status)) (break status))
  (def configured (global-environment base-environment root))
  (def target (global-file base-environment))
  (def config-home (or (get base-environment "XDG_CONFIG_HOME")
                      (string (get base-environment "HOME") "/.config")))
  (def legacy (string config-home "/ds/mise"))
  (def sources (array ;(reverse (global-fragments (merge configured {"MISE_CONFIG_DIR" legacy})))))
  (array/push sources (string legacy "/config.toml"))
  (def saved (selection/active-layers generated/catalog base-environment))
  (def profiles (layers/profiles generated/catalog (string/join (tuple ;saved layer) ",")))
  (each profile (reverse profiles)
    (array/push sources (string (config-root root) "/mise." profile ".toml")))
  (array/push sources (string (config-root root) "/mise.toml"))
  (when (owned-profile? target)
    (def contents (slurp target))
    (def pending (string target ".ds-" (os/getpid)))
    (spit pending contents)
    (os/rename pending target))
  (tool-config/seed mise configured target sources (global-fragments configured))
  (retire-profiles (get configured "MISE_CONFIG_DIR"))
  (process/execute runner @[mise "-C" "/" "install"] configured))
