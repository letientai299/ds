(import scripts/lib/filesystem)
(import scripts/lib/layers)

(defn config-home [environment]
  (or (get environment "XDG_CONFIG_HOME")
      (string (or (get environment "HOME") (error "HOME is required")) "/.config")))

(defn state-path [environment]
  (string (config-home environment) "/ds/components"))

(defn selected [catalog environment]
  (def target (state-path environment))
  (def result @[])
  (when (os/stat target)
    (each line (string/split "\n" (string (slurp target)))
      (def name (string/trim line))
      (unless (empty? name)
        (def component (keyword name))
        # This file is written by an earlier version of ds and read by every
        # command. A name that a later catalog dropped must not turn `ds add`
        # or `ds status` into a crash with no way to clear the file.
        (if-not (layers/optional-component? catalog component)
          (eprint (string "ds: ignoring unknown selected component: " name))
          (unless (find |(= $ component) result)
            (array/push result component))))))
  result)

(defn selected? [catalog environment component]
  (not= nil (find |(= $ component) (selected catalog environment))))

(defn save [environment components]
  (def target (state-path environment))
  (if (empty? components)
    (when (os/stat target) (os/rm target))
    (do
      (filesystem/ensure-parent target)
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
  (def environments (layers/profiles catalog layer))
  (each component (selected catalog environment)
    (array/push environments (string component)))
  (each component extras
    (unless (find |(= $ (string component)) environments)
      (array/push environments (string component))))
  (string/join environments ","))

(defn layer-path [environment]
  (string (config-home environment) "/ds/layer"))

(defn active-layers [catalog environment &opt fallback]
  (def target (layer-path environment))
  (if (os/lstat target)
    (let [names (string/split "," (string/trim (string (slurp target))))]
      (each name names
        (unless (layers/known-layer? catalog name)
          (error (string "invalid saved layer: " name))))
      (distinct names))
    (or fallback [])))

(defn combine [catalog current target]
  (def names (string/split "," target))
  (distinct (tuple ;current ;(if (find |(= $ "all") names)
                             (map string (filter |(not= $ :all) (sort (keys (get catalog :layers)))))
                             names))))
