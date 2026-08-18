(import scripts/generated/layers :as generated)
(import scripts/lib/docker)
(import scripts/lib/layers :as layers)
(import scripts/lib/managed)
(import scripts/lib/mise)
(import scripts/lib/planner)
(import scripts/lib/platform)
(import scripts/lib/selection)

(layers/validate generated/catalog)

(defn usage []
  (print "usage: ds <status|diff|apply|adopt|force|add|unapply|doctor|shell|shell-init|docker-rootful> [layer|component] [--dry-run]"))

(defn fail [message]
  (eprint (string "ds: " message))
  (os/exit 1))

(defn parse-apply [args]
  (when (< (length args) 3)
    (fail "apply requires a layer"))
  (def layer (get args 2))
  (var dry-run? false)
  (var skips @[])
  (var index 3)
  (while (< index (length args))
    (def arg (get args index))
    (case arg
      "--dry-run" (set dry-run? true)
      "--skip"
      (do
        (set index (+ index 1))
        (when (>= index (length args)) (fail "--skip requires a component"))
        (array/push skips (keyword (get args index))))
      (fail (string "unknown argument: " arg)))
    (set index (+ index 1)))
  [layer dry-run? skips])

(defn print-plan [operation layer components]
  (print (string operation " " layer ":"))
  (each component components
    (print (string "  " component))))

(def root (or (os/getenv "DS_ROOT") (error "DS_ROOT is required")))
(def base-environment (os/environ))

(defn quiet-runner [argv environment]
  (def sink (file/open (if (= (get environment "DS_OS") "Windows") "NUL" "/dev/null") :w))
  (put environment :out sink)
  (put environment :err sink)
  (def status (os/execute argv :pe environment))
  (file/close sink)
  status)

(defn foreground-runner [argv environment]
  (os/execute argv :pe environment))

(defn commands-present? [commands probe]
  (all probe commands))

(defn command-present? [environment command]
  (def separator (if (= (get environment "DS_OS") "Windows") ";" ":"))
  (def suffix (if (= (get environment "DS_OS") "Windows") ".exe" ""))
  (var present? false)
  (each directory (string/split separator (or (get environment "PATH") ""))
    (when (os/stat (string directory "/" command suffix))
      (set present? true)))
  present?)

(defn capture-runner [argv environment]
  (def target (mise/copy-environment environment))
  (def sink (file/open (if (= (get environment "DS_OS") "Windows") "NUL" "/dev/null") :w))
  (put target :out :pipe)
  (put target :err sink)
  (def proc (os/spawn argv :pe target))
  (def output (string (ev/read (get proc :out) :all)))
  (def status (os/proc-wait proc))
  (os/proc-close proc)
  (file/close sink)
  [status output])

(defn current-user []
  (or (get base-environment "USER")
      (get base-environment "LOGNAME")
      (get base-environment "DS_UID")
      "unknown"))

(defn linger-enabled? []
  (not= nil (os/stat (string "/var/lib/systemd/linger/" (current-user)))))

(defn docker-rootless? []
  (if-not (command-present? base-environment "docker")
    false
    (let [result (capture-runner
                   ["docker" "info" "--format" "{{json .SecurityOptions}}"]
                   base-environment)]
      (and (= 0 (get result 0)) (string/find "rootless" (get result 1))))))

(defn docker-engine-ready? []
  (and (command-present? base-environment "docker")
       (= 0 (quiet-runner ["docker" "info"] (mise/copy-environment base-environment)))
       (= 0 (quiet-runner ["docker" "buildx" "version"] (mise/copy-environment base-environment)))
       (= 0 (quiet-runner ["docker" "compose" "version"] (mise/copy-environment base-environment)))))

(defn docker-ready? []
  (and (docker-engine-ready?)
       (or (not (docker-rootless?)) (linger-enabled?))))

(defn slurp-or-empty [path]
  (if (os/stat path) (string (slurp path)) ""))

(defn docker-facts []
  (def uid (or (get base-environment "DS_UID") "unknown"))
  (def user (or (get base-environment "USER") (get base-environment "LOGNAME") uid))
  (def runtime (get base-environment "XDG_RUNTIME_DIR"))
  (def os-name (or (get base-environment "DS_OS")
                   (if (os/which :macos) "Darwin" "Linux")))
  {:ready? (docker-ready?)
   :engine-ready? (docker-engine-ready?)
   :rootless? (docker-rootless?)
   :os (platform/normalize-os os-name)
   :uid uid
   :user user
   :command? (fn [command] (command-present? base-environment command))
   :subids? (and (docker/subid-range? (slurp-or-empty "/etc/subuid") user uid)
                 (docker/subid-range? (slurp-or-empty "/etc/subgid") user uid))
   :runtime? (and runtime (os/stat runtime))
   :linger? (linger-enabled?)})

(defn docker-plan []
  (docker/plan (docker-facts)))

(defn print-docker-diagnostic [state]
  (def user (or (get base-environment "USER") (get base-environment "LOGNAME") "this user"))
  (print (string "docker: " (docker/diagnostic state user))))

(defn converge-docker []
  (def state (docker-plan))
  (case state
    :reuse (print-docker-diagnostic state)
    :install-rootless
    (try
      (do
        (docker/install-rootless foreground-runner base-environment)
        (if-not (docker-engine-ready?)
          (print-docker-diagnostic :failed)
          (if (get (docker-facts) :linger?)
            (print-docker-diagnostic :reuse)
            (print-docker-diagnostic :needs-linger))))
      ([err]
       (eprint (string "docker: " err))
       (print-docker-diagnostic :failed)))
    (print-docker-diagnostic state)))

(defn component-probe [layer component]
  (def spec (get (get generated/catalog :components) component))
  (def commands (get spec :commands))
  (case (get spec :owner)
    :runtime (if (os/stat (mise/binary root base-environment)) :present :missing)
    :native (if (if (= component :docker)
                  (docker-ready?)
                  (commands-present? commands (fn [command] (command-present? base-environment command))))
              :present
              :missing)
    :mise (if (mise/tool-installed? root layer base-environment (or (get spec :tool) component))
            :present
            :missing)
    :unavailable))

(defn inspect-layer [layer]
  (def components (layers/resolve generated/catalog layer []))
  (planner/inspect components (fn [component] (component-probe layer component))))

(defn optional-component? [name]
  (layers/optional-component? generated/catalog (keyword name)))

(defn current-layer []
  (def target (string (selection/config-home base-environment) "/ds/layer"))
  (if (os/stat target)
    (let [value (string/trim (string (slurp target)))]
      (if (find |(= $ value) ["core" "remote"]) value "core"))
    "core"))

(defn optional-state [name]
  (def component (keyword name))
  (if (and (selection/selected? generated/catalog base-environment component)
           (= :present (component-probe (current-layer) component)))
    :complete
    :incomplete))

(defn print-optional-status [name]
  (print (string name ": " (optional-state name)))
  (print (string "  "
                 (if (selection/selected? generated/catalog base-environment (keyword name))
                   "selected "
                   "unselected ")
                 name)))

(defn combined-summary [package-entries file-entries]
  (cond
    (find |(= :conflict (get $ :state)) file-entries) :conflict
    (or (not= :complete (planner/summary package-entries))
        (find |(not= :present (get $ :state)) file-entries)) :incomplete
    :else :complete))

(defn print-status [layer entries file-entries]
  (print (string layer ": " (combined-summary entries file-entries)))
  (each entry entries
    (print (string "  " (get entry :state) " " (get entry :component))))
  (each entry file-entries
    (print (string "  " (get entry :state) " " (get entry :target)))))

(defn print-diff [layer entries file-entries]
  (print (string "diff " layer ":"))
  (each action (planner/diff entries)
    (case (get action :action)
      :install (print (string "  + " (get action :component)))
      :blocked (print (string "  ! " (get action :component) " conflict"))
      :unavailable (print (string "  ? " (get action :component) " unavailable"))))
  (each entry file-entries
    (case (get entry :state)
      :missing (print (string "  + " (get entry :target)))
      :conflict (print (string "  ! " (get entry :target) " conflict"))
      :unavailable (print (string "  ? " (get entry :source) " unavailable")))))

(defn print-shell-init []
  (def ds-path (string root "/ds"))
  (print (string "export DS_DS=\"" ds-path "\""))
  (print "if [ -r \"${XDG_CONFIG_HOME:-$HOME/.config}/ds/shell.zsh\" ]; then")
  (print "  source \"${XDG_CONFIG_HOME:-$HOME/.config}/ds/shell.zsh\"")
  (print "fi")
  (print "ds() {")
  (print "  command \"$DS_DS\" \"$@\"")
  (print "  local exit_status=$?")
  (print "  case \"$1:$exit_status\" in apply:0|add:0) eval \"$(command \"$DS_DS\" shell-init)\" ;; esac")
  (print "  return $exit_status")
  (print "}"))

(defn main [& args]
  (when (< (length args) 2)
    (usage)
    (os/exit 1))
  (def command (get args 1))
  (case command
    "status"
    (do
      (when (< (length args) 3)
        (fail "status requires a layer"))
      (def layer (get args 2))
      (if (optional-component? layer)
        (print-optional-status layer)
        (print-status layer (inspect-layer layer) (managed/inspect root base-environment layer))))

    "diff"
    (do
      (when (< (length args) 3)
        (fail "diff requires a layer"))
      (def layer (get args 2))
      (if (optional-component? layer)
        (do
          (print (string "diff " layer ":"))
          (unless (= :complete (optional-state layer))
            (print (string "  + " layer))))
        (print-diff layer (inspect-layer layer) (managed/inspect root base-environment layer))))

    "apply"
    (do
      (def parsed (parse-apply args))
      (def layer (get parsed 0))
      (def components (filter (fn [component] (not (find |(= $ component) (get parsed 2))))
                              (layers/resolve generated/catalog layer [])))
      (if (get parsed 1)
        (do
          (print-plan "would apply" layer components)
          (each entry (managed/inspect root base-environment layer)
            (unless (= :present (get entry :state))
              (print (string "  " (get entry :state) " " (get entry :target))))))
        (do
          (unless (empty? (managed/conflicts root base-environment layer))
            (fail (string "managed-file conflict: "
                          (get (first (managed/conflicts root base-environment layer)) :target))))
          (def status (mise/apply foreground-runner root layer base-environment false))
          (unless (= status 0)
            (fail (string "mise bootstrap failed with status " status)))
          (try
            (managed/apply foreground-runner root base-environment layer)
            ([err] (fail err)))
          (when (and (= layer "remote")
                     (not (find |(= $ :docker) (get parsed 2))))
            (converge-docker))
          (print (string "applied " layer)))))

    "unapply"
    (do
      (when (< (length args) 3)
        (fail "unapply requires a layer"))
      (def target (get args 2))
      (if (optional-component? target)
        (do
          (selection/remove generated/catalog base-environment (keyword target))
          (print (string "unapplied " target)))
        (do
          (managed/unapply foreground-runner root base-environment target)
          (when (= target "core")
            (selection/save base-environment []))
          (print (string "unapplied " target)))))

    "adopt"
    (do
      (def parsed (parse-apply args))
      (def layer (get parsed 0))
      (if (get parsed 1)
        (each entry (managed/conflicts root base-environment layer)
          (print (string "would adopt " (get entry :target) " -> " (managed/backup-path entry))))
        (do
          (def status (mise/apply foreground-runner root layer base-environment false))
          (unless (= status 0) (fail (string "mise bootstrap failed with status " status)))
          (managed/prepare foreground-runner root base-environment layer :adopt)
          (managed/apply foreground-runner root base-environment layer)
          (print (string "adopted and applied " layer)))))

    "force"
    (do
      (def parsed (parse-apply args))
      (def layer (get parsed 0))
      (if (get parsed 1)
        (each entry (managed/conflicts root base-environment layer)
          (print (string "would replace " (get entry :target))))
        (do
          (def status (mise/apply foreground-runner root layer base-environment false))
          (unless (= status 0) (fail (string "mise bootstrap failed with status " status)))
          (managed/prepare foreground-runner root base-environment layer :force)
          (managed/apply foreground-runner root base-environment layer)
          (print (string "forced and applied " layer)))))

    "shell-init" (print-shell-init)

    "doctor"
    (do
      (def layer (if (< (length args) 3) "core" (get args 2)))
      (if (optional-component? layer)
        (print-optional-status layer)
        (do
          (print-status layer (inspect-layer layer) (managed/inspect root base-environment layer))
          (when (= layer "remote") (print-docker-diagnostic (docker-plan))))))

    "add"
    (do
      (when (< (length args) 3)
        (fail "add requires a component"))
      (def component (get args 2))
      (unless (optional-component? component)
        (fail (string "unknown optional component: " component)))
      (if (and (> (length args) 3) (= "--dry-run" (get args 3)))
        (print (string "would add " component))
        (do
          (def profile (selection/profile generated/catalog base-environment (current-layer) [(keyword component)]))
          (def status (mise/apply foreground-runner root profile base-environment false))
          (unless (= status 0)
            (fail (string "mise bootstrap failed with status " status)))
          (selection/add generated/catalog base-environment (keyword component))
          (print (string "added " component)))))

    "shell"
    (do
      (def status (os/execute ["zsh" "-i"] :pe base-environment))
      (os/exit status))

    "docker-rootful"
    (do
      (unless (and (= "--approve-rootful" (get args 2))
                   (= "--grant-docker-group" (get args 3)))
        (fail "docker-rootful requires --approve-rootful --grant-docker-group"))
      (def user (or (get base-environment "USER") (get base-environment "LOGNAME")))
      (unless user (fail "USER or LOGNAME is required"))
      (def environment (mise/copy-environment base-environment))
      (put environment "DS_TARGET_USER" user)
      (def status (foreground-runner
                    [(string root "/src/scripts/docker-rootful.sh")
                     "--approve-rootful" "--grant-docker-group"]
                    environment))
      (unless (= status 0) (fail (string "rootful Docker provisioning failed with status " status))))

    (do
      (usage)
      (fail (string "unknown command: " command)))))
