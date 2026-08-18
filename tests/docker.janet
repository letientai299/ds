(import scripts/lib/docker)

(defn assert= [expected actual message]
  (unless (= expected actual)
    (error (string message ": expected " expected ", got " actual))))

(defn facts [& pairs]
  (merge {:ready? false
          :engine-ready? false
          :rootless? false
          :linger? false
          :os :linux
          :uid "1000"
          :command? (fn [_command] true)
          :subids? true
          :runtime? true}
         (table ;pairs)))

(assert= :reuse (docker/plan (facts :ready? true)) "existing daemon wins")
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

(assert= true
         (not= nil (docker/subid-range? "user:100000:65536\n" "user" "1000"))
         "valid user range")
(assert= nil (docker/subid-range? "user:100000:65535\n" "user" "1000") "short range")

(def calls @[])
(defn runner [argv _environment]
  (array/push calls argv)
  0)
(docker/install-rootless runner {})
(assert= ["dockerd-rootless-setuptool.sh" "install"] (first calls) "setup order")
(assert= ["systemctl" "--user" "enable" "--now" "docker.service"] (last calls) "service order")

(print "docker planner: ok")
