(import scripts/lib/filesystem)
(import scripts/lib/planner)
(import scripts/lib/process)

(defn assert= [expected actual message]
  (unless (= expected actual)
    (error (string message ": expected " expected ", got " actual))))

(def entries
  (planner/inspect [:mise :neovim :fd]
                   (fn [component] (if (= component :mise) :present :missing))))
(assert= :incomplete (planner/summary entries) "missing components are incomplete")
(def actions (planner/diff entries))
(assert= 2 (length actions) "diff includes only missing components")
(assert= :neovim (get (first actions) :component) "diff preserves component order")

(def conflict
  (planner/inspect [:mise] (fn [_component] :conflict)))
(assert= :conflict (planner/summary conflict) "conflicts dominate summary")
(assert= :blocked (get (first (planner/diff conflict)) :action) "conflicts block apply")

(def fake-root "/isolated/home")

# A relative target would make the walk start at the filesystem root.
(var relative-failed? false)
(try
  (filesystem/ensure-parent "relative/target")
  ([_err] (set relative-failed? true)))
(assert= true relative-failed? "ensure-parent rejects a relative target")

(def calls @[])
(defn fake-runner [argv environment]
  (array/push calls [argv environment])
  0)
(assert= 0
         (process/execute fake-runner ["git" "clone" "source" "target with spaces"] {"HOME" fake-root})
         "injected process runner result")
(assert= "target with spaces" (get (get (first calls) 0) 3) "arguments remain an argv")

(print "harness: ok")
