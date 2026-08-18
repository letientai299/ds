(import scripts/generated/support)
(import scripts/lib/platform)

(defn assert= [expected actual message]
  (unless (= expected actual)
    (error (string message ": expected " expected ", got " actual))))

(def alpine (platform/classify {:os "Linux" :arch "aarch64" :libc "musl"}))
(assert= :musl (get alpine :libc) "Alpine libc")
(assert= "linux-arm64-musl" (platform/runtime-platform alpine) "Alpine runtime")

(def ubuntu (platform/classify {:os "Linux" :arch "x86_64" :libc "glibc"}))
(assert= :glibc (get ubuntu :libc) "Ubuntu libc")
(assert= "linux-x64-musl" (platform/runtime-platform ubuntu) "Ubuntu static runtime")

(def macos (platform/classify {:os "Darwin" :arch "arm64" :libc nil}))
(assert= :system (get macos :libc) "macOS system libc")
(assert= "macos-arm64" (platform/runtime-platform macos) "macOS runtime")

(defn fake-exists [present]
  (fn [path] (not= nil (find (fn [candidate] (= candidate path)) present))))

(def probed-alpine
  (platform/probe
    {"DS_OS" "Linux" "DS_ARCH" "x86_64"}
    (fake-exists ["/lib/ld-musl-x86_64.so.1"])))
(assert= :musl (get probed-alpine :libc) "probed Alpine libc")

(def probed-ubuntu
  (platform/probe
    {"DS_OS" "Linux" "DS_ARCH" "aarch64"}
    (fake-exists ["/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1"])))
(assert= :glibc (get probed-ubuntu :libc) "probed Ubuntu libc")

(assert= 6 (length (get support/support :targets)) "supported target count")
(each target (get support/support :targets)
  (def runtime (platform/runtime-platform target))
  (unless (string? runtime)
    (error "supported target has no runtime")))
(assert= :unprivileged
         (get-in support/support [:bootstrap :privilege])
         "bootstrap privilege")
(assert= :explicit-approval
         (get-in support/support [:rootful :policy])
         "rootful policy")

(print "platforms: ok")
