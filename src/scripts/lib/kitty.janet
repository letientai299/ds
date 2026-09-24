(import scripts/lib/process)

(defn unsupported [environment]
  (cond
    (or (= "musl" (get environment "DS_LIBC")) (os/stat "/etc/alpine-release"))
    "Kitty requires macOS or glibc Linux"
    (= "Darwin" (get environment "DS_OS")) nil
    :else
    (let [probe (process/capture ["getconf" "GNU_LIBC_VERSION"] environment 2)
          version (last (string/split " " (string/trim (get probe :output ""))))
          parts (string/split "." version)
          major (scan-number (get parts 0 ""))
          minor (scan-number (get parts 1 ""))]
      (unless (and (= :ok (get probe :state)) major minor
                   (or (> major 2) (and (= major 2) (>= minor 35))))
        "Kitty requires glibc 2.35 or newer"))))
