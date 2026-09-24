(import scripts/lib/activation)
(import scripts/lib/filesystem)
(import scripts/lib/managed)
(import scripts/lib/mise)
(import scripts/lib/selection)

(def required
  {:packages [:profile :components] :takeover [:entry :mode] :write [:entry]
   :remove [:entry] :restore [:entry :backup] :select [:components :target]
   :activate [:root] :docker [] :directory [:target] :blocked [:target :reason]})

(defn valid-entry? [entry]
  (and (or (table? entry) (struct? entry))
       (string? (get entry :target))
       (case (get entry :kind)
         :link (string? (get entry :source))
         :command-link (string? (get entry :source))
         :marker (string? (get entry :line))
         :layer (find |(= $ (get entry :contents)) ["core" "remote"])
         false)))

(defn action [tag fields]
  (unless (has-key? required tag) (error (string "invalid action: " tag)))
  (each key (get required tag)
    (def value (get fields key))
    (unless (case key
              :entry (valid-entry? value)
              :mode (find |(= $ value) [:adopt :force])
              :components (and (or (array? value) (tuple? value)) (all keyword? value))
              (string? value))
      (error (string "invalid action field: " key))))
  (merge fields {:action tag}))

(defn removal [entry]
  (def target (get entry :target))
  (case (get entry :kind)
    :link (managed/same-link? target (get entry :source))
    :command-link (managed/same-link? target (get entry :source))
    :marker (= :present (managed/state entry))
    :layer (and (= :file (os/lstat target :mode))
                (find |(= $ (string/trim (string (slurp target)))) ["core" "remote"]))))

(defn files [root environment layer mode]
  (def plan @[])
  (each entry (managed/inspect root environment layer)
    (def state (get entry :state))
    (case state
      :unavailable (array/push plan (action :blocked {:target (get entry :target) :reason "source unavailable"}))
      :conflict
      (cond
        (= mode :apply)
        (array/push plan (action :blocked {:target (get entry :target) :reason (string "conflict; preview: ds apply " layer " --force --dry-run")}))
        (and (= mode :adopt) (os/lstat (managed/backup-path entry)))
        (array/push plan (action :blocked {:target (managed/backup-path entry) :reason "backup exists"}))
        :else (array/push plan (action :takeover {:entry entry :mode mode}))))
    (unless (= state :present) (array/push plan (action :write {:entry entry}))))
  plan)

(defn build [catalog root environment request]
  (def mode (get request :mode))
  (unless (find |(= $ mode) [:apply :adopt :force :unapply :add])
    (error "invalid mutation mode"))
  (def layer (get request :layer))
  (def selected (selection/selected catalog environment))
  (def component (get request :component))
  (def plan @[])
  (def activate? (and (not (get environment "DS_SHELL_STATE")) (activation/prefix root)))
  (when (and (not= mode :unapply) (not component) activate?)
    (try
      (do (activation/candidate (activation/prefix root) (last (string/split "/" root)))
          (activation/link-version (activation/prefix root) "current")
          (activation/link-version (activation/prefix root) "previous"))
      ([err] (array/push plan (action :blocked {:target (activation/prefix root) :reason (string err)})))))
  (cond
    (= mode :unapply)
    (if component
      (array/push plan (action :select {:target (selection/state-path environment) :components (filter |(not= $ component) selected)}))
      (do
        (each entry (reverse (managed/entries root environment layer))
          (def remove? (removal entry))
          (when remove? (array/push plan (action :remove {:entry entry})))
          (def backup (managed/backup-path entry))
          (def marker-remains?
            (and (= :marker (get entry :kind)) (= :file (os/lstat (get entry :target) :mode))
                 (not (empty? (string/replace (managed/marker-block (get entry :line)) ""
                                             (string (slurp (get entry :target))))))))
          (when (and (os/lstat backup) (not marker-remains?)
                     (or remove? (not (os/lstat (get entry :target)))))
            (array/push plan (action :restore {:entry entry :backup backup}))))
        (when (= layer "core") (array/push plan (action :select {:target (selection/state-path environment) :components []})))))
    :else
    (do
      (array/push plan (action :packages
        {:profile (selection/profile catalog environment layer (if component [component] []))
         :components (filter |(and (not= $ :docker)
                                  (not= :runtime (get-in catalog [:components $ :owner])))
                              (get request :components))}))
      (if component
        (array/push plan (action :select {:target (selection/state-path environment) :components (distinct (tuple ;selected component))}))
        (do
          (array/concat plan (files root environment layer mode))
          (array/push plan (action :directory
            {:target (string (or (get environment "DS_SHELL_STATE")
                                 (get environment "XDG_STATE_HOME")
                                 (string (get environment "HOME") "/.local/state")) "/zsh/history")}))
          (when (get request :docker) (array/push plan (action :docker {})))
          (when activate? (array/push plan (action :activate {:root root})))))))
  plan)

(defn describe [item]
  (def entry (get item :entry))
  (def target (get entry :target))
  (case (get item :action)
    :packages (string "packages " (string/join (map string (get item :components)) ", ")
                      " (mise bootstrap profile " (get item :profile) ")")
    :takeover (if (= :adopt (get item :mode))
                (string "backup " target " -> " (managed/backup-path entry))
                (string (if (managed/marker-file? entry) "replace managed block " "replace ") target " (no backup)"))
    :write (string (get entry :kind) " " target
                   (case (get entry :kind)
                     :layer (string " = " (get entry :contents))
                     :marker " (append managed block)"
                     (string " -> " (get entry :source))))
    :remove (string "remove " (get entry :kind) " " target)
    :restore (string "restore " (get item :backup) " -> " target)
    :select (string (if (empty? (get item :components)) "remove " "write ") (get item :target) " selection " (string/join (map string (get item :components)) ", "))
    :directory (string "ensure parent " (get item :target))
    :activate (string "activate " (get item :root) " (save current as previous)")
    :docker "converge Docker readiness"
    :blocked (string "blocked " (get item :target) ": " (get item :reason))))

(defn execute [plan runner root environment docker-runner]
  (def blocked (find |(= :blocked (get $ :action)) plan))
  (when blocked (error (describe blocked)))
  (each item plan
    (def entry (get item :entry))
    (def target (get entry :target))
    (case (get item :action)
      :packages
      (let [status (mise/apply runner root (get item :profile) environment false)]
        (unless (= 0 status) (error (string "mise bootstrap failed with status " status))))
      :takeover (managed/prepare-entry runner environment entry (get item :mode))
      :write (managed/apply-entry entry)
      :remove (case (get entry :kind)
                :marker (managed/remove-marker target (get entry :line))
                :layer (os/rm target)
                (managed/release-link entry))
      :restore (unless (= 0 (runner ["mv" "--" (get item :backup) target] environment))
                 (error (string "could not restore: " target)))
      :select (selection/save environment (get item :components))
      :directory (filesystem/ensure-parent (get item :target))
      :docker (docker-runner)
      :activate (activation/activate (get item :root))
      (error "invalid executable action"))))
