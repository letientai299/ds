# Creates every missing parent directory of an absolute target path.
# Both former copies of this walk prefixed "/" to each segment, so a relative
# target silently walked from the filesystem root; reject that instead.
(defn ensure-parent [target]
  (unless (string/has-prefix? "/" target)
    (error (string "target path must be absolute: " target)))
  (def parts (string/split "/" target))
  (var current "")
  (each part (slice parts 0 -2)
    (unless (empty? part)
      (set current (string current "/" part))
      (os/mkdir current)))
  true)
