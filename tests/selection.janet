(import scripts/generated/layers :as generated)
(import scripts/lib/selection)

(defn assert= [expected actual message]
  (unless (= expected actual)
    (error (string message ": expected " expected ", got " actual))))

(def home (or (os/getenv "DF_TEST_HOME") (error "DF_TEST_HOME is required")))
(def environment {"HOME" home "XDG_CONFIG_HOME" (string home "/config")})
(os/mkdir home)

(assert= "" (selection/profile generated/catalog environment "core" []) "empty core profile")
(selection/add generated/catalog environment :starship)
(assert= true (selection/selected? generated/catalog environment :starship) "selection persists")
(assert= "starship" (selection/profile generated/catalog environment "core" []) "core optional profile")
(assert= "remote,starship" (selection/profile generated/catalog environment "remote" []) "remote optional profile")
(selection/remove generated/catalog environment :starship)
(assert= false (selection/selected? generated/catalog environment :starship) "selection removes")
(assert= nil (os/stat (selection/state-path environment)) "empty selection removes state file")

(print "selection: ok")
