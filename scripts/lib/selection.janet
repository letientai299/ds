(import scripts/lib/layers)

(defn config-home [environment]
  (or (get environment "XDG_CONFIG_HOME")
      (string (or (get environment "HOME") (error "HOME is required")) "/.config")))

(defn state-path [environment]
  (string (config-home environment) "/df/components"))

(defn selected [catalog environment]
  (def target (state-path environment))
  (def result @[])
  (when (os/stat target)
    (each line (string/split "\n" (string (slurp target)))
      (def name (string/trim line))
      (unless (empty? name)
        (def component (keyword name))
        (unless (layers/optional-component? catalog component)
          (error (string "unknown selected component: " name)))
        (unless (find |(= $ component) result)
          (array/push result component)))))
  result)

(defn selected? [catalog environment component]
  (not= nil (find |(= $ component) (selected catalog environment))))

(defn ensure-parent [target]
  (def parts (string/split "/" target))
  (var current "")
  (each part (slice parts 0 (- (length parts) 1))
    (unless (empty? part)
      (set current (string current "/" part))
      (os/mkdir current))))

(defn save [environment components]
  (def target (state-path environment))
  (if (empty? components)
    (when (os/stat target) (os/rm target))
    (do
      (ensure-parent target)
      (spit target (string (string/join (map string components) "\n") "\n"))))
  true)

(defn add [catalog environment component]
  (unless (layers/optional-component? catalog component)
    (error (string "unknown optional component: " component)))
  (def components (selected catalog environment))
  (unless (find |(= $ component) components)
    (array/push components component))
  (save environment components))

(defn remove [catalog environment component]
  (save environment (filter |(not= $ component) (selected catalog environment))))

(defn profile [catalog environment layer extras]
  (def environments @[])
  (unless (= layer "core") (array/push environments layer))
  (each component (selected catalog environment)
    (array/push environments (string component)))
  (each component extras
    (unless (find |(= $ (string component)) environments)
      (array/push environments (string component))))
  (string/join environments ","))
