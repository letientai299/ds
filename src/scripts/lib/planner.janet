(def valid-states {:present true :installed true :outdated true :missing true :conflict true :unavailable true})

(defn inspect [components probe]
  (def entries @[])
  (each component components
    (def result (probe component))
    (def details (if (keyword? result) {:state result} result))
    (def state (get details :state))
    (unless (has-key? valid-states state)
      (error (string "invalid component state: " state)))
    (array/push entries (merge details {:component component})))
  entries)

(defn summary [entries]
  (var result :complete)
  (each entry entries
    (case (get entry :state)
      :conflict (set result :conflict)
      :unavailable (unless (= result :conflict) (set result :incomplete))
      :outdated (unless (= result :conflict) (set result :incomplete))
      :missing (unless (= result :conflict) (set result :incomplete))))
  result)

(defn diff [entries]
  (def actions @[])
  (each entry entries
    (case (get entry :state)
      :present nil
      :installed nil
      :outdated (array/push actions @{:component (get entry :component) :action :update})
      :missing (array/push actions @{:component (get entry :component) :action :install})
      :conflict (array/push actions @{:component (get entry :component) :action :blocked})
      :unavailable (array/push actions @{:component (get entry :component) :action :unavailable})))
  actions)
