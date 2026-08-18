(defn safe-relative? [path]
  (and
    (> (length path) 0)
    (not= (first path) (chr "/"))
    (all (fn [part] (and (> (length part) 0) (not= part ".") (not= part "..")))
         (string/split "/" path))))

(defn rooted-path [root relative]
  (unless (safe-relative? relative)
    (error (string "unsafe relative path: " relative)))
  (if (= (last root) (chr "/"))
    (string root relative)
    (string root "/" relative)))

(defn exists-in? [root relative exists?]
  (exists? (rooted-path root relative)))
