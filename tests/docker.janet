(import scripts/lib/docker)

(defn assert= [expected actual message]
  (unless (= expected actual)
    (error (string message ": expected " expected ", got " actual))))

(defn facts [& pairs]
  (merge {:engine-ready? false
          :rootless? false
          :linger? false
          :os :linux
          :uid "1000"
          :command? (fn [_command] true)
          :subids? true
          :runtime? true}
         (table ;pairs)))

(assert= :reuse (docker/plan (facts :engine-ready? true)) "existing rootful daemon wins")
(assert= :reuse
         (docker/plan (facts :engine-ready? true :rootless? true :linger? true))
         "rootless daemon with linger wins")
(assert= :needs-linger
         (docker/plan (facts :engine-ready? true :rootless? true))
         "rootless daemon without linger is incomplete")
(assert= :unsupported (docker/plan (facts :os :macos)) "macOS never provisions a daemon")
(assert= :root-user (docker/plan (facts :uid "0")) "root is not a rootless target")
(assert= :missing-tools
         (docker/plan (facts :command? (fn [command] (not= command "newuidmap"))))
         "missing prerequisite is reported")
(assert= :missing-subids (docker/plan (facts :subids? false)) "subids are required")
(assert= :missing-runtime (docker/plan (facts :runtime? false)) "login runtime is required")
(assert= :install-rootless (docker/plan (facts)) "satisfied prerequisites install")

(def subid-cases
  [["user:100000:65536\n" true "valid user range"]
   ["1000:100000:65536\n" true "range matched by uid"]
   ["user:100000:65535\n" false "short range"]
   ["other:100000:65536\n" false "range belongs to another user"]
   ["user:100000:abc\n" false "non-numeric count"]
   ["user:100000:65536\r\n" false "CRLF-terminated count"]
   ["user:100000\n" false "truncated record"]
   ["" false "empty file"]])

(each [contents expected message] subid-cases
  (assert= expected
           (not= nil (docker/subid-range? contents "user" "1000"))
           (string "subid range: " message)))

(def calls @[])
(defn runner [argv _environment]
  (array/push calls argv)
  0)
(docker/install-rootless runner {})
(assert= ["dockerd-rootless-setuptool.sh" "install"] (first calls) "setup order")
(assert= ["systemctl" "--user" "enable" "--now" "docker.service"] (last calls) "service order")

(print "docker planner: ok")
