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
(def observed @[])
(defn fake-exists [path]
  (array/push observed path)
  (= path "/isolated/home/.config/ds/config"))
(assert= true
         (filesystem/exists-in? fake-root ".config/ds/config" fake-exists)
         "filesystem probe uses injected root")
(assert= 1 (length observed) "filesystem probe count")
(assert= "/isolated/home/.config/ds/config" (first observed) "filesystem probe stays isolated")

(var unsafe-failed? false)
(try
  (filesystem/rooted-path fake-root "../real-home")
  ([_err] (set unsafe-failed? true)))
(assert= true unsafe-failed? "filesystem root rejects traversal")

(def calls @[])
(defn fake-runner [argv environment]
  (array/push calls [argv environment])
  0)
(assert= 0
         (process/execute fake-runner ["git" "clone" "source" "target with spaces"] {"HOME" fake-root})
         "injected process runner result")
(assert= "target with spaces" (get (get (first calls) 0) 3) "arguments remain an argv")

(print "harness: ok")
