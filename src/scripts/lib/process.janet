(defn valid-argv? [argv]
  (and
    (> (length argv) 0)
    (all (fn [argument] (and (string? argument) (> (length argument) 0))) argv)))

(defn execute [runner argv environment]
  (unless (valid-argv? argv)
    (error "process arguments must be a non-empty sequence of non-empty strings"))
  (runner argv environment))
