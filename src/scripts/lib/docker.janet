(def required-commands
  ["docker" "dockerd-rootless-setuptool.sh" "newuidmap" "newgidmap" "systemctl"])

(defn subid-range? [contents user uid]
  (find
    (fn [line]
      (def fields (string/split ":" line))
      (and (= 3 (length fields))
           (or (= user (get fields 0)) (= uid (get fields 0)))
           # scan-number yields nil for a non-numeric or CRLF-terminated count,
           # and Janet orders nil above every number, so >= alone accepts it.
           (let [count (scan-number (get fields 2))]
             (and (number? count) (>= count 65536)))))
    (string/split "\n" contents)))

(defn ready? [facts]
  (and (get facts :engine-ready?)
       (or (not (get facts :rootless?)) (get facts :linger?))))

(defn plan [facts]
  (cond
    (ready? facts) :reuse
    (and (get facts :engine-ready?)
         (get facts :rootless?)
         (not (get facts :linger?))) :needs-linger
    (not= :linux (get facts :os)) :unsupported
    (= "0" (get facts :uid)) :root-user
    (not (all (get facts :command?) required-commands)) :missing-tools
    (not (get facts :subids?)) :missing-subids
    (not (get facts :runtime?)) :missing-runtime
    :else :install-rootless))

(defn install-rootless [runner environment]
  (unless (= 0 (runner ["dockerd-rootless-setuptool.sh" "install"] environment))
    (error "rootless Docker setup failed"))
  (unless (= 0 (runner ["systemctl" "--user" "enable" "--now" "docker.service"] environment))
    (error "rootless Docker user service failed"))
  true)

(defn diagnostic [state user]
  (case state
    :reuse "Docker daemon, Compose, and Buildx are ready"
    :unsupported "Docker provisioning is unavailable on this platform; reuse an existing daemon"
    :root-user "rootless Docker requires an unprivileged login user"
    :missing-tools "rootless Docker needs docker, dockerd-rootless-setuptool.sh, uidmap, and user systemd"
    :missing-subids (string "rootless Docker needs at least 65536 subordinate UIDs and GIDs for " user)
    :missing-runtime "rootless Docker needs a writable XDG_RUNTIME_DIR from a real login session"
    :needs-linger (string "enable SSH persistence explicitly: sudo loginctl enable-linger " user)
    :install-rootless "rootless Docker can be installed"
    :failed "Docker setup completed but readiness checks still fail"))
