(import scripts/generated/layers :as generated)
(import scripts/lib/selection)

(def fixture (merge generated/catalog {:optional [:example] :components (merge (get generated/catalog :components) {:example {:commands ["example"] :owner :mise}})}))

(defn assert= [expected actual message]
  (unless (= expected actual)
    (error (string message ": expected " expected ", got " actual))))

(def home (or (os/getenv "DS_TEST_HOME") (error "DS_TEST_HOME is required")))
(def environment {"HOME" home "XDG_CONFIG_HOME" (string home "/config")})
(os/mkdir home)

(assert= "core" (selection/profile fixture environment "core" []) "empty core profile")
(selection/add fixture environment :example)
(assert= true (selection/selected? fixture environment :example) "selection persists")
(assert= "core,example" (selection/profile fixture environment "core" []) "core optional profile")
(assert= "core,remote,example" (selection/profile fixture environment "remote" []) "remote optional profile")
(selection/remove fixture environment :example)
(assert= false (selection/selected? fixture environment :example) "selection removes")
(assert= nil (os/stat (selection/state-path environment)) "empty selection removes state file")

# State written by another version must not turn every command into a crash,
# because no command can clear the file once it does.
(selection/save environment [:example])
(spit (selection/state-path environment) "example\nretired-component\n")
(assert= [:example]
         (tuple ;(selection/selected fixture environment))
         "unknown selected component is skipped, not fatal")
(assert= "core,example"
         (selection/profile fixture environment "core" [])
         "profile ignores the unknown component")
(selection/remove fixture environment :example)

(print "selection: ok")
