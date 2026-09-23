(import scripts/lib/inventory)
(import scripts/lib/json)
(import scripts/lib/process)

(each construct [(fn [] (inventory/tool-state "/missing" {:commands ["x"]}))]
  (var rejected false)
  (try (construct) ([_err] (set rejected true)))
  (assert rejected "invalid state accepted"))
(assert (= "\"a\\u000ab\\\"\\\\\"" (json/encode "a\nb\"\\")) "JSON escaping")
(def start (os/clock))
(assert (= :timeout (get (process/capture ["sh" "-c" "exec sleep 10"] (os/environ) 0.05) :state))
        "process timeout not classified")
(assert (< (- (os/clock) start) 2) "process exceeded deadline")
