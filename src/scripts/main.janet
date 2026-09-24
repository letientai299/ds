(import scripts/lib/activation)
(import scripts/lib/help)
(import scripts/lib/inventory)
(import scripts/lib/json)
(import scripts/lib/mutation)
(import scripts/lib/process)
(import scripts/generated/layers :as generated)
(import scripts/lib/docker)
(import scripts/lib/layers :as layers)
(import scripts/lib/managed)
(import scripts/lib/mise)
(import scripts/lib/planner)
(import scripts/lib/platform)
(import scripts/lib/selection)
(import scripts/lib/shell)

(layers/validate generated/catalog)

(defn fail [message]
  (eprint (string "ds: " message))
  (os/exit 2))

(def root (or (os/getenv "DS_ROOT") (error "DS_ROOT is required")))

(defn catalog-names [key]
  (string/join
    (sort (map string (if (= key :layers)
                        (keys (get generated/catalog :layers))
                        (get generated/catalog :optional))))
    ", "))

(defn controller? []
  (not= nil (os/stat (string root "/src/bundle/controller.sh"))))

(defn usage [emit]
  (help/usage emit generated/catalog (controller?) false))

(defn known-layer? [name]
  (layers/known-layer? generated/catalog name))

(defn parse-mutation [command args]
  (var target nil)
  (var dry-run? false)
  (var mode (case command "remove" "unapply" "force" "adopt" command))
  (def skips @[])
  (var index 2)
  (while (< index (length args))
    (def arg (if (= (get args index) "--adopt") "--force" (get args index)))
    (case arg
      "--dry-run" (set dry-run? true)
      "--force" (do
                  (unless (= command "apply") (fail "--force requires apply"))
                  (set mode "adopt"))
      "--skip" (do
                 (unless (= command "apply") (fail (string command " does not accept --skip")))
                 (++ index)
                 (unless (= "docker" (get args index)) (fail "--skip requires docker"))
                 (array/push skips :docker))
      (if (or target (string/has-prefix? "-" arg))
        (fail (string "unexpected argument: " arg))
        (set target arg)))
    (++ index))
  (when (and (nil? target) (not= command "apply"))
    (fail (string command " requires a target")))
  {:target target :dry-run dry-run? :skips skips :mode (keyword mode)})

(defn reject-extra [args maximum]
  (when (> (length args) maximum)
    (fail (string "unexpected argument: " (get args maximum)))))

(def base-environment (os/environ))

(defn foreground-runner [argv environment]
  (os/execute argv :pe environment))

(defn commands-present? [commands probe]
  (all probe commands))

(defn command-present? [environment command]
  (def separator (if (= (get environment "DS_OS") "Windows") ";" ":"))
  (def suffix (if (= (get environment "DS_OS") "Windows") ".exe" ""))
  (not= nil
    (find (fn [directory]
            (managed/executable-file?
              (string (if (empty? directory) "." directory) "/" command suffix)))
          (string/split separator (or (get environment "PATH") "")))))

(defn current-user []
  (or (get base-environment "USER")
      (get base-environment "LOGNAME")
      (get base-environment "DS_UID")
      "unknown"))

(defn linger-enabled? []
  (not= nil (os/stat (string "/var/lib/systemd/linger/" (current-user)))))

(defn probe-docker-engine []
  (if-not (command-present? base-environment "docker")
    {:engine-ready? false :rootless? false :probe :missing}
    (let [info (process/capture ["docker" "info" "--format" "{{json .SecurityOptions}}"] base-environment 3)
          extensions (if (= :ok (get info :state))
                       (map (fn [name] (process/capture ["docker" name "version"] base-environment 3))
                            ["buildx" "compose"]) [])
          probe (cond
                  (= :timeout (get info :state)) :timeout
                  (not= :ok (get info :state)) :unreachable
                  (find |(= :timeout (get $ :state)) extensions) :timeout
                  (find |(not= :ok (get $ :state)) extensions) :missing-plugin
                  :else :ready)]
      {:engine-ready? (= probe :ready) :probe probe
       :rootless? (and (= :ok (get info :state)) (not= nil (string/find "rootless" (get info :output))))})))

(defn slurp-or-empty [path]
  (if (os/stat path) (string (slurp path)) ""))

(defn probe-docker-facts []
  (def uid (or (get base-environment "DS_UID") "unknown"))
  (def user (or (get base-environment "USER") (get base-environment "LOGNAME") uid))
  (def runtime (get base-environment "XDG_RUNTIME_DIR"))
  (def os-name (or (get base-environment "DS_OS")
                   (if (os/which :macos) "Darwin" "Linux")))
  (merge (probe-docker-engine)
  {:os (platform/normalize-os os-name)
   :uid uid
   :user user
   :command? (fn [command] (command-present? base-environment command))
   :subids? (and (docker/subid-range? (slurp-or-empty "/etc/subuid") user uid)
                 (docker/subid-range? (slurp-or-empty "/etc/subgid") user uid))
   :runtime? (and runtime (os/stat runtime))
   :linger? (linger-enabled?)}))

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
  (print (string "docker: " (docker/diagnostic state user)))
  (print (string "docker probe: " (get (docker-facts) :probe))))

(defn converge-docker []
  (def state (docker-plan))
  (case state
    :reuse (print-docker-diagnostic state)
    :install-rootless
    (try
      (do
        (docker/install-rootless foreground-runner base-environment)
        (if-not (get (probe-docker-engine) :engine-ready?)
          (print-docker-diagnostic :failed)
          (if (linger-enabled?)
            (print-docker-diagnostic :reuse)
            (print-docker-diagnostic :needs-linger))))
      ([err]
       (eprint (string "docker: " err))
       (print-docker-diagnostic :failed)))
    (print-docker-diagnostic state)))

(var cached-inventory nil)

(defn tool-inventory []
  (when (nil? cached-inventory)
    (set cached-inventory (inventory/collect generated/catalog root base-environment)))
  cached-inventory)

(defn component-probe [_layer component]
  (def spec (get (get generated/catalog :components) component))
  (def commands (get spec :commands))
  (case (get spec :owner)
    :runtime {:state (if (managed/executable-file? (mise/binary root base-environment)) :installed :missing)}
    :native (if (= component :docker)
              (let [probe (get (docker-facts) :probe)]
                {:state (case probe :ready :installed :missing :missing :unavailable) :probe probe})
              {:state (if (commands-present? commands (fn [command] (command-present? base-environment command)))
                        :installed :missing)})
    :mise (get (tool-inventory) component)
    {:state :unavailable}))

(defn inspect-layer [layer]
  (def components (layers/resolve generated/catalog layer
                                  (map string (selection/selected generated/catalog base-environment))))
  (planner/inspect components (fn [component] (component-probe layer component))))

(defn optional-component? [name]
  (layers/optional-component? generated/catalog (keyword name)))

(defn current-layer []
  (def target (string (selection/config-home base-environment) "/ds/layer"))
  (if (os/lstat target)
    (let [value (string/trim (string (slurp target)))]
      (unless (known-layer? value) (fail (string "invalid saved layer: " value)))
      value)
    "core"))

(defn optional-state [name]
  (def component (keyword name))
  (if (and (selection/selected? generated/catalog base-environment component)
           (= :installed (get (component-probe (current-layer) component) :state)))
    :complete
    :incomplete))

(defn print-component [entry]
  (print (string "  " (get entry :state) " " (get entry :component)
                 (if (get entry :expected) (string " (expected " (get entry :expected) ")") ""))))

(defn print-optional-status [name]
  (print (string name ": " (optional-state name)))
  (print-component (merge (component-probe (current-layer) (keyword name)) {:component (keyword name)}))
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

(defn print-entries [entries file-entries]
  (each entry entries (print-component entry))
  (each entry file-entries
    (print (string "  " (get entry :state) " " (get entry :target)))))

(defn print-status [layer entries file-entries]
  (print (string layer ": " (combined-summary entries file-entries)))
  (print-entries entries file-entries))

(defn print-context [layer emit]
  (emit (string "scope: " (if (get base-environment "DS_SHELL_STATE") "trial configuration" "normal configuration")))
  (emit (string "layer: " layer))
  (emit (string "configuration: " (selection/config-home base-environment)))
  (when (get base-environment "DS_SHELL_STATE")
    (emit "Package installations affect the host.")))

(defn print-diff [layer entries file-entries]
  (print (string "diff " layer ":"))
  (each action (planner/diff entries)
    (case (get action :action)
      :update (print (string "  ~ " (get action :component) " outdated"))
      :install (print (string "  + " (get action :component)))
      :blocked (print (string "  ! " (get action :component) " conflict"))
      :unavailable (print (string "  ? " (get action :component) " unavailable"))))
  (each entry file-entries
    (case (get entry :state)
      :missing (print (string "  + " (get entry :target)))
      :conflict (print (string "  ! " (get entry :target) " conflict"))
      :unavailable (print (string "  ? " (get entry :source) " unavailable")))))

(defn print-shell-init []
  (def ds-path (string (if (get base-environment "DS_SHELL_STATE") root (managed/link-root root)) "/ds"))
  (print (string "export DS_DS=\"" ds-path "\""))
  (print "if [ -r \"${XDG_CONFIG_HOME:-$HOME/.config}/ds/shell.zsh\" ]; then")
  (print "  source \"${XDG_CONFIG_HOME:-$HOME/.config}/ds/shell.zsh\"")
  (print "fi")
  (print (string (slurp (string root "/src/dotfiles/command.sh")))))

(defn require-target [name]
  (unless (or (optional-component? name) (known-layer? name))
    (fail (string "unknown layer or component: " name
                  " (layers: " (catalog-names :layers)
                  "; optional components: " (catalog-names :optional) ")")))
  name)

(defn run-mutation [command args]
  (def parsed (parse-mutation command args))
  (def target (require-target (or (get parsed :target) (current-layer))))
  (def component (if (optional-component? target) (keyword target) nil))
  (def mode (if (and component (= :apply (get parsed :mode))) :add (get parsed :mode)))
  (when (and (= command "add") (not component))
    (fail "add requires an optional component"))
  (when (and component (or (find |(= mode $) [:adopt :force])
                           (not (empty? (get parsed :skips)))))
    (fail "Conflict policies and --skip require a layer"))
  (def layer (if component (current-layer) target))
  (def components (filter (fn [item] (not (find |(= $ item) (get parsed :skips))))
                         (layers/resolve generated/catalog layer
                           (map string (distinct (tuple ;(selection/selected generated/catalog base-environment)
                                                        ;(if component [component] [])))))))
  (def request {:mode mode :layer layer :component component :components components
                :docker (and (= layer "remote") (not (find |(= $ :docker) (get parsed :skips))))})
  (when (find |(= command $) ["apply" "remove"]) (print-context layer print))
  (defn work []
    (def plan (mutation/build generated/catalog root base-environment request))
    (if (get parsed :dry-run)
      (do
        (print (string "would " command " " target (if (find |(= command $) ["unapply" "add" "remove"]) "" ":")))
        (each item plan (print (string "  " (mutation/describe item)))))
      (do
        (mutation/execute plan foreground-runner root base-environment converge-docker)
        (print (string (case command "apply" "applied" "adopt" "adopted and applied"
                             "force" "forced and applied" "add" "added" "unapply" "unapplied"
                             "remove" "removed") " " target)))))
  (try
    (if (get parsed :dry-run) (work)
      (activation/with-lock (or (activation/prefix root)
                               (string (selection/config-home base-environment) "/ds")) work))
    ([err] (eprint (string "ds: " err)) (os/exit 1))))

(defn switch-version [command args]
  (var base (or (activation/prefix root)
                (string (or (get base-environment "XDG_DATA_HOME")
                            (string (get base-environment "HOME") "/.local/share")) "/ds")))
  (var preview false)
  (var name nil)
  (var index 2)
  (when (= command "activate")
    (set name (get args index))
    (unless name (fail "activate requires a version"))
    (++ index))
  (while (< index (length args))
    (case (get args index)
      "--dry-run" (set preview true)
      "--prefix" (do (++ index) (set base (get args index)) (unless base (fail "--prefix requires a path")))
      (fail (string "unknown argument: " (get args index))))
    (++ index))
  (when (empty? base) (fail "--prefix requires a non-empty path"))
  (unless (string/has-prefix? "/" base) (set base (string (os/cwd) "/" base)))
  (defn work []
    (when (= command "rollback")
      (set name (or (activation/link-version base "previous") (error "no previous version"))))
    (def candidate (activation/candidate base name))
    (activation/link-version base "current")
    (activation/link-version base "previous")
    (if preview (print (string "would activate " candidate))
      (do (activation/activate candidate) (print (string "activated " candidate)))))
  (try (if preview (work) (activation/with-lock base work))
       ([err] (eprint (string "ds: " err)) (os/exit 1))))

(defn report-status [args]
  (var target nil)
  (var json? false)
  (var check? false)
  (var verbose? false)
  (each arg (slice args 2)
    (case arg
      "--json" (set json? true)
      "--check" (set check? true)
      "--verbose" (set verbose? true)
      (if (or target (string/has-prefix? "-" arg))
        (fail (string "unexpected argument: " arg))
        (set target arg))))
  (set target (require-target (or target (current-layer))))
  (def optional? (optional-component? target))
  (def layer (if optional? (current-layer) target))
  (def packages (if optional?
                  (planner/inspect [(keyword target)] |(component-probe layer $))
                  (inspect-layer target)))
  (def files (if optional? [] (managed/inspect root base-environment target)))
  (def summary (if optional? (optional-state target) (combined-summary packages files)))
  (if json?
    (print (json/encode {:schema 1 :target target :summary summary :components packages
                          :files files :selected (selection/selected generated/catalog base-environment)}))
    (do
      (print-context layer print)
      (print (string target ": " summary))
      (print-entries (if verbose? packages (filter |(not= :installed (get $ :state)) packages))
                     (if verbose? files (filter |(not= :present (get $ :state)) files)))
      (when optional?
        (def selected? (selection/selected? generated/catalog base-environment (keyword target)))
        (when (or verbose? (not selected?))
          (print (string "  " (if selected? "selected " "unselected ") target))))
      (when (and verbose? (not optional?) (= layer "remote"))
        (print-docker-diagnostic (docker-plan)))
      (unless (= summary :complete)
        (if (find |(= :unavailable (get $ :state)) files)
          (print "Resolve unavailable configuration sources before applying.")
          (print (string "preview: ds apply " target
                         (if (= summary :conflict) " --force" "") " --dry-run"))))))
  (when check? (os/exit (if (= summary :complete) 0 1))))

(defn help-request? [args]
  (var requested? false)
  (each arg (slice args 2)
    (when (= arg "--") (break))
    (when (find |(= arg $) ["--help" "-h"]) (set requested? true)))
  requested?)

(defn start-shell [args]
  (var docker? false)
  (var passthrough? false)
  (def forwarded @[])
  (each arg (slice args 2)
    (if (and (not passthrough?) (= arg "--docker"))
      (set docker? true)
      (array/push forwarded arg))
    (when (= arg "--") (set passthrough? true)))
  (if docker?
    (do
      (unless (controller?) (fail "--docker requires a controller checkout"))
      (os/posix-exec [(string root "/src/bundle/docker.sh") ;forwarded] :pe base-environment))
    (do
      (reject-extra args 2)
      (shell/start root base-environment generated/catalog))))

(defn main [& args]
  (when (< (length args) 2)
    (try (shell/start root base-environment generated/catalog)
         ([err] (fail err))))
  (def command (get args 1))
  (when (and (help/specification command (controller?)) (help-request? args))
    (help/show command generated/catalog (controller?))
    (break))
  (case command
    "help" (do (reject-extra args 3)
               (case (get args 2)
                 nil (usage print)
                 "--all" (help/usage print generated/catalog (controller?) true)
                 (if (help/specification (get args 2) (controller?))
                   (help/show (get args 2) generated/catalog (controller?))
                   (fail (string "unavailable command: " (get args 2))))))
    "--help" (do (reject-extra args 2) (usage print))
    "-h" (do (reject-extra args 2) (usage print))
    "status" (report-status args)
    "stage" (os/exit (foreground-runner
                       ["sh" (string root "/src/bootstrap.sh") ;(slice args 2)] base-environment))
    "activate" (switch-version command args)
    "rollback" (switch-version command args)
    "completion" (do (reject-extra args 3)
                      (try (help/complete (get args 2) generated/catalog (controller?))
                           ([err] (fail err))))

    "diff"
    (do
      (reject-extra args 3)
      (when (< (length args) 3)
        (fail "diff requires a layer"))
      (def layer (require-target (get args 2)))
      (if (optional-component? layer)
        (do
          (print (string "diff " layer ":"))
          (unless (= :complete (optional-state layer))
            (print (string "  + " layer))))
        (print-diff layer (inspect-layer layer) (managed/inspect root base-environment layer))))

    "apply" (run-mutation command args)
    "adopt" (run-mutation command args)
    "force" (run-mutation command args)
    "remove" (run-mutation command args)
    "unapply" (run-mutation command args)
    "add" (run-mutation command args)

    "shell-init" (do (reject-extra args 2) (print-shell-init))

    "doctor"
    (do
      (reject-extra args 3)
      (def layer (if (< (length args) 3) "core" (require-target (get args 2))))
      (if (optional-component? layer)
        (print-optional-status layer)
        (do
          (print-status layer (inspect-layer layer) (managed/inspect root base-environment layer))
          (when (= layer "remote") (print-docker-diagnostic (docker-plan))))))

    "shell" (try (start-shell args) ([err] (fail err)))

    "docker-rootful"
    (do
      (reject-extra args 4)
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
