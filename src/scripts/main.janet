(import scripts/generated/layers :as generated)
(import scripts/lib/docker)
(import scripts/lib/layers :as layers)
(import scripts/lib/managed)
(import scripts/lib/mise)
(import scripts/lib/planner)
(import scripts/lib/platform)
(import scripts/lib/selection)

(layers/validate generated/catalog)

(defn fail [message]
  (eprint (string "ds: " message))
  (os/exit 1))

(def root (or (os/getenv "DS_ROOT") (error "DS_ROOT is required")))

(defn catalog-names [key]
  (string/join
    (sort (map string (if (= key :layers)
                        (keys (get generated/catalog :layers))
                        (get generated/catalog :optional))))
    ", "))

# A delivered snapshot carries no docs, so this is the only discovery surface
# on a target. `push` is dispatched by the launcher and exists only in a
# controller checkout, so it is listed only where it works.
(defn usage [emit]
  (each line
    ["usage: ds <command> [layer|component] [options]"
     ""
     "commands:"
     "  status LAYER             report component and managed-file state"
     "  diff LAYER               show missing, conflicting, and unavailable entries"
     "  doctor [LAYER]           status plus Docker diagnostics for remote"
     "  apply LAYER              converge a layer"
     "  adopt LAYER              back up conflicting targets, then converge"
     "  force LAYER              destructively replace conflicting targets, then converge"
     "  add COMPONENT            enable an optional component"
     "  unapply LAYER|COMPONENT  remove exact managed state or an optional selection"
     "  shell                    start an interactive Zsh with the current environment"
     "  shell-init               print the Zsh integration fragment"
     "  docker-rootful           provision rootful Docker behind two approval flags"]
    (emit line))
  (when (os/stat (string root "/src/bundle/controller.sh"))
    (emit "  push HOST LAYER          deliver and apply from a controller checkout"))
  (each line
    [""
     "options:"
     "  --dry-run                preview without changing anything"
     "  --skip docker            leave Docker convergence to the operator"
     ""
     (string "layers: " (catalog-names :layers))
     (string "optional components: " (catalog-names :optional))]
    (emit line)))

(defn known-layer? [name]
  (layers/known-layer? generated/catalog name))

(defn require-layer [name]
  (unless (known-layer? name)
    (fail (string "unknown layer: " name " (known layers: " (catalog-names :layers) ")")))
  name)

# `--skip` can only honour components ds converges itself. Everything else is
# installed by `mise bootstrap` as one profile, so accepting it would be a lie.
(def skippable [:docker])

(defn parse-layer-args [command args]
  (when (< (length args) 3)
    (fail (string command " requires a layer")))
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
        (def component (keyword (get args index)))
        (unless (find |(= $ component) skippable)
          (fail (string "--skip does not accept " (get args index)
                        " (skippable components: "
                        (string/join (sort (map string skippable)) ", ") ")")))
        (array/push skips component))
      (fail (string "unknown argument: " arg)))
    (set index (+ index 1)))
  [layer dry-run? skips])

(defn parse-takeover-args [command args]
  (def parsed (parse-layer-args command args))
  (unless (empty? (get parsed 2))
    (fail (string command " does not accept --skip")))
  parsed)

(defn print-plan [operation layer components]
  (print (string operation " " layer ":"))
  (each component components
    (print (string "  " component))))

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


(defn slurp-or-empty [path]
  (if (os/stat path) (string (slurp path)) ""))

(defn probe-docker-facts []
  (def uid (or (get base-environment "DS_UID") "unknown"))
  (def user (or (get base-environment "USER") (get base-environment "LOGNAME") uid))
  (def runtime (get base-environment "XDG_RUNTIME_DIR"))
  (def os-name (or (get base-environment "DS_OS")
                   (if (os/which :macos) "Darwin" "Linux")))
  {:engine-ready? (docker-engine-ready?)
   :rootless? (docker-rootless?)
   :os (platform/normalize-os os-name)
   :uid uid
   :user user
   :command? (fn [command] (command-present? base-environment command))
   :subids? (and (docker/subid-range? (slurp-or-empty "/etc/subuid") user uid)
                 (docker/subid-range? (slurp-or-empty "/etc/subgid") user uid))
   :runtime? (and runtime (os/stat runtime))
   :linger? (linger-enabled?)})

# Each field costs a daemon round trip and component-probe runs inside a map,
# so the record is sampled once per process. Sampling it once also keeps the
# fields mutually consistent.
(var cached-docker-facts nil)

(defn docker-facts []
  (when (nil? cached-docker-facts)
    (set cached-docker-facts (probe-docker-facts)))
  cached-docker-facts)

(defn docker-ready? []
  (docker/ready? (docker-facts)))

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
          (if (linger-enabled?)
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
  (def components (layers/resolve generated/catalog layer
                                  (map string (selection/selected generated/catalog base-environment))))
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
  (def ds-path (string (managed/link-root root) "/ds"))
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

(defn require-target [name]
  (unless (or (optional-component? name) (known-layer? name))
    (fail (string "unknown layer or component: " name
                  " (layers: " (catalog-names :layers)
                  "; optional components: " (catalog-names :optional) ")")))
  name)

(defn main [& args]
  (when (< (length args) 2)
    (usage eprint)
    (os/exit 1))
  (def command (get args 1))
  (case command
    "help" (usage print)
    "--help" (usage print)
    "-h" (usage print)

    "status"
    (do
      (when (< (length args) 3)
        (fail "status requires a layer"))
      (def layer (require-target (get args 2)))
      (if (optional-component? layer)
        (print-optional-status layer)
        (print-status layer (inspect-layer layer) (managed/inspect root base-environment layer))))

    "diff"
    (do
      (when (< (length args) 3)
        (fail "diff requires a layer"))
      (def layer (require-target (get args 2)))
      (if (optional-component? layer)
        (do
          (print (string "diff " layer ":"))
          (unless (= :complete (optional-state layer))
            (print (string "  + " layer))))
        (print-diff layer (inspect-layer layer) (managed/inspect root base-environment layer))))

    "apply"
    (do
      (def parsed (parse-layer-args "apply" args))
      (def layer (require-layer (get parsed 0)))
      (def components (filter (fn [component] (not (find |(= $ component) (get parsed 2))))
                              (layers/resolve generated/catalog layer
                                              (map string (selection/selected generated/catalog base-environment)))))
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
          (def profile (selection/profile generated/catalog base-environment layer []))
          (def status (mise/apply foreground-runner root profile base-environment false))
          (unless (= status 0)
            (fail (string "mise bootstrap failed with status " status)))
          (try
            (managed/apply root base-environment layer)
            ([err] (fail err)))
          (when (and (= layer "remote")
                     (not (find |(= $ :docker) (get parsed 2))))
            (converge-docker))
          (print (string "applied " layer)))))

    "unapply"
    (do
      (when (< (length args) 3)
        (fail "unapply requires a layer"))
      (def target (require-target (get args 2)))
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
      (def parsed (parse-takeover-args "adopt" args))
      (def layer (require-layer (get parsed 0)))
      (if (get parsed 1)
        (each entry (managed/conflicts root base-environment layer)
          (print (string "would adopt " (get entry :target) " -> " (managed/backup-path entry))))
        (do
          (def profile (selection/profile generated/catalog base-environment layer []))
          (def status (mise/apply foreground-runner root profile base-environment false))
          (unless (= status 0) (fail (string "mise bootstrap failed with status " status)))
          (managed/prepare foreground-runner root base-environment layer :adopt)
          (managed/apply root base-environment layer)
          (print (string "adopted and applied " layer)))))

    "force"
    (do
      (def parsed (parse-takeover-args "force" args))
      (def layer (require-layer (get parsed 0)))
      (if (get parsed 1)
        (each entry (managed/conflicts root base-environment layer)
          (print (string "would replace " (get entry :target))))
        (do
          (def profile (selection/profile generated/catalog base-environment layer []))
          (def status (mise/apply foreground-runner root profile base-environment false))
          (unless (= status 0) (fail (string "mise bootstrap failed with status " status)))
          (managed/prepare foreground-runner root base-environment layer :force)
          (managed/apply root base-environment layer)
          (print (string "forced and applied " layer)))))

    "shell-init" (print-shell-init)

    "doctor"
    (do
      (def layer (if (< (length args) 3) "core" (require-target (get args 2))))
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
        (fail (string "unknown optional component: " component
                      " (optional components: " (catalog-names :optional) ")")))
      (var dry-run? false)
      (each arg (slice args 3)
        (if (= "--dry-run" arg)
          (set dry-run? true)
          (fail (string "unknown argument: " arg))))
      (if dry-run?
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
      (usage eprint)
      (fail (string "unknown command: " command)))))
