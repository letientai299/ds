(import scripts/lib/managed)
(import scripts/lib/mise)
(import scripts/lib/process)
(import scripts/lib/tool-config)

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
    (error "mise component requires a version"))
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
  (def configured (mise/global-environment environment root))
  (def data (get configured "MISE_DATA_DIR"))
  (def executable (mise/binary root configured))
  (def tools @{})
  (each file (tuple (mise/global-file environment) ;(mise/global-fragments configured))
    (when (os/stat file)
      (try
        (each name (keys (tool-config/read-tools executable configured file))
          (put tools name name))
        ([_err] nil))))
  (def result @{})
  (eachp [component spec] (get catalog :components)
    (when (= :mise (get spec :owner))
      (def name (string (or (get spec :tool) component)))
      (def tool (if (string/has-prefix? "http-" name) (string "http:" (slice name 5)) name))
      (def configured-tool
        (when (not (empty? tools))
          (or (get tools tool)
              (some |(get tools $) (tool-config/identities executable configured tool)))))
      (put result component
        (try
          (if configured-tool
            (let [resolved (process/capture [executable "-C" "/" "where" configured-tool] configured 10)
                  path (string/trim (get resolved :output ""))
                  found (= :ok (get resolved :state))
                  version (if found (last (string/split "/" path)) "configured")
                  commands (if found (binaries path (get spec :commands)) [])]
              {:state (if (and (not (empty? commands)) (all identity commands)) :installed :missing)
               :expected version :installed (if found [version] []) :executables commands})
            (tool-state (string data "/installs/" name) spec))
             ([err] {:state :unavailable :reason (string err)})))))
  result)
