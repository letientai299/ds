(import scripts/lib/mise)

(defn assert= [expected actual message]
  (unless (= expected actual)
    (error (string message ": expected " expected ", got " actual))))

(def base
  {"HOME" "/isolated/home"
   "DF_OS" "Linux"
   "DF_ARCH" "x86_64"
   "PATH" "/usr/bin"})
(def configured (mise/environment base "/snapshot" "core"))
(assert= "/isolated/home/.config/df/mise" (get configured "MISE_CONFIG_DIR") "isolated config")
(assert= "/isolated/home/.local/share/mise" (get configured "MISE_DATA_DIR") "isolated data")
(assert= "/snapshot" (get configured "MISE_GLOBAL_CONFIG_ROOT") "global config root")
(assert= "/snapshot" (get configured "MISE_TRUSTED_CONFIG_PATHS") "trusted root")
(assert= "" (get configured "MISE_ENV") "core environment")
(assert= "/snapshot/runtime/bin/linux-x64-musl/mise"
         (mise/binary "/snapshot" configured)
         "static Linux mise")

(def calls @[])
(defn fake-runner [argv environment]
  (array/push calls [argv environment])
  0)
(assert= 0 (mise/apply fake-runner "/snapshot" "remote" base true) "dry-run result")
(def apply-call (first calls))
(assert= ["/snapshot/runtime/bin/linux-x64-musl/mise"
          "-C" "/snapshot" "bootstrap" "--yes" "--dry-run"]
         (tuple ;(get apply-call 0))
         "bootstrap argv")
(assert= "remote" (get (get apply-call 1) "MISE_ENV") "remote environment")

(print "mise: ok")
