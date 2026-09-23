(import scripts/lib/platform)
(import scripts/lib/process)

(defn copy-environment [source]
  (def target @{})
  (eachp [key value] source
    (put target key value))
  target)

(defn env-path [environment key fallback]
  (or (get environment key) fallback))

# The payload mise profiles live beside each other so MISE_ENV can select
# mise.remote.toml and mise.starship.toml next to mise.toml.
(defn config-root [root]
  (string root "/src/mise"))

(defn environment [base root layer]
  (def result (copy-environment base))
  (def home (or (get result "HOME") (error "HOME is required")))
  (def config-home (env-path result "XDG_CONFIG_HOME" (string home "/.config")))
  (def data-home (env-path result "XDG_DATA_HOME" (string home "/.local/share")))
  (def state-home (env-path result "XDG_STATE_HOME" (string home "/.local/state")))
  (def cache-home (env-path result "XDG_CACHE_HOME" (string home "/.cache")))
  (put result "MISE_CACHE_DIR" (env-path result "MISE_CACHE_DIR" (string cache-home "/mise")))
  (put result "MISE_CONFIG_DIR" (env-path result "MISE_CONFIG_DIR" (string config-home "/ds/mise")))
  (put result "MISE_DATA_DIR" (env-path result "MISE_DATA_DIR" (string data-home "/mise")))
  (put result "MISE_STATE_DIR" (env-path result "MISE_STATE_DIR" (string state-home "/mise")))
  (put result "MISE_SYSTEM_CONFIG_DIR" (string config-home "/ds/mise-system"))
  (put result "MISE_OVERRIDE_CONFIG_FILENAMES" "mise.toml")
  (put result "MISE_GLOBAL_CONFIG_ROOT" (config-root root))
  (put result "MISE_TRUSTED_CONFIG_PATHS" (config-root root))
  (put result "MISE_YES" "1")
  (put result "MISE_ENV" (if (= layer "core") "" layer))
  result)

(defn binary [root environment]
  (or
    (get environment "DS_MISE")
    (let [target (platform/runtime-platform
                   {:os (platform/normalize-os (get environment "DS_OS"))
                    :arch (platform/normalize-arch (get environment "DS_ARCH"))})
          bundled (string root "/src/runtime/bin/" target "/mise")
          checkout (string root "/dist/runtime/bin/" target "/mise")]
      (if (os/stat bundled)
        bundled
        (if (os/stat checkout) checkout bundled)))))

(defn bootstrap-argv [mise root dry-run?]
  (def argv @[mise "-C" (config-root root) "bootstrap" "--yes"])
  (when dry-run?
    (array/push argv "--dry-run"))
  argv)

(defn apply [runner root layer base-environment dry-run?]
  (def target-environment (environment base-environment root layer))
  (def mise (binary root target-environment))
  (process/execute runner (bootstrap-argv mise root dry-run?) target-environment))
