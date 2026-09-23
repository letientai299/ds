(defn valid-argv? [argv]
  (and
    (> (length argv) 0)
    (all (fn [argument] (and (string? argument) (> (length argument) 0))) argv)))

(defn execute [runner argv environment]
  (unless (valid-argv? argv)
    (error "process arguments must be a non-empty sequence of non-empty strings"))
  (runner argv environment))

(defn capture [argv environment seconds]
  (unless (valid-argv? argv) (error "invalid process arguments"))
  (def target (merge environment {:out :pipe}))
  (def sink (file/open "/dev/null" :w))
  (put target :err sink)
  (var proc nil)
  (def result
    (try
      (do
        (set proc (os/spawn argv :pe target))
        (ev/with-deadline seconds
          (def output (string (ev/read (get proc :out) :all)))
          (def status (os/proc-wait proc))
          {:state (if (= status 0) :ok :failed) :status status :output output}))
      ([err]
       (when proc (try (os/proc-kill proc) ([_ignored] nil)))
       {:state (if (= err "deadline expired") :timeout :unavailable) :reason (string err)})))
  (when proc (os/proc-close proc))
  (file/close sink)
  result)
