(import scripts/lib/managed)
(import scripts/lib/mise)

(defn binaries [directory commands]
  (def roots @[directory (string directory "/bin")])
  (when (= :directory (os/stat directory :mode))
    (each child (sort (os/dir directory))
      (def path (string directory "/" child))
      (when (and (not (string/has-prefix? "." child)) (= :directory (os/lstat path :mode)))
        (array/push roots path (string path "/bin")))))
  (map (fn [command]
         (find managed/executable-file? (map |(string $ "/" command) roots))) commands))

(defn tool-state [directory spec]
  (def expected (get spec :version))
  (unless (and (string? expected) (not (empty? expected)))
    (error "mise component requires a pinned version"))
  (def path (string directory "/" expected))
  (def executables (binaries path (get spec :commands)))
  (def installed (if (= :directory (os/stat directory :mode))
                   (sort (filter (fn [version]
                                   (and (= :directory (os/lstat (string directory "/" version) :mode))
                                        (not (string/has-prefix? "." version))
                                        (all identity (binaries (string directory "/" version)
                                                                (get spec :commands)))))
                                 (os/dir directory))) []))
  {:state (cond (all identity executables) :installed
                (os/stat path) :unavailable
                (not (empty? installed)) :outdated
                :else :missing)
   :expected expected :installed installed :executables executables})

(defn collect [catalog root environment]
  (def data (get (mise/environment environment root "core") "MISE_DATA_DIR"))
  (def result @{})
  (eachp [component spec] (get catalog :components)
    (when (= :mise (get spec :owner))
      (put result component
        (try (tool-state (string data "/installs/" (or (get spec :tool) component)) spec)
             ([err] {:state :unavailable :reason (string err)})))))
  result)
