# JSON output for status records.
(defn quote-string [value]
  (def output @"\"")
  (each byte (string/bytes (string value))
    (case byte
      34 (buffer/push-string output "\\\"")
      92 (buffer/push-string output "\\\\")
      (if (< byte 32)
        (buffer/push-string output (string/format "\\u%04x" byte))
        (buffer/push-byte output byte))))
  (buffer/push-string output "\"")
  (string output))

(defn encode [value]
  (cond
    (nil? value) "null"
    (true? value) "true"
    (false? value) "false"
    (number? value) (string value)
    (or (string? value) (keyword? value)) (quote-string value)
    (or (array? value) (tuple? value)) (string "[" (string/join (map encode value) ",") "]")
    (or (table? value) (struct? value))
    (string "{" (string/join (map (fn [key] (string (quote-string key) ":" (encode (get value key))))
                                  (sort (keys value))) ",") "}")
    :else (error "unsupported JSON value")))
