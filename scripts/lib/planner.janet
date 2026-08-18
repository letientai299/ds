(def valid-states {:present true :missing true :conflict true :unavailable true})

(defn inspect [components probe]
  (def entries @[])
  (each component components
    (def state (probe component))
    (unless (has-key? valid-states state)
      (error (string "invalid component state: " state)))
    (array/push entries @{:component component :state state}))
  entries)

(defn summary [entries]
  (var result :complete)
  (each entry entries
    (case (get entry :state)
      :conflict (set result :conflict)
      :unavailable (unless (= result :conflict) (set result :incomplete))
      :missing (unless (= result :conflict) (set result :incomplete))))
  result)

(defn diff [entries]
  (def actions @[])
  (each entry entries
    (case (get entry :state)
      :present nil
      :missing (array/push actions @{:component (get entry :component) :action :install})
      :conflict (array/push actions @{:component (get entry :component) :action :blocked})
      :unavailable (array/push actions @{:component (get entry :component) :action :unavailable})))
  actions)
