(defn normalize-os [name]
  (case name
    "Darwin" :macos
    :darwin :macos
    :macos :macos
    "Linux" :linux
    :linux :linux
    (error (string "unsupported operating system: " name))))

(defn normalize-arch [name]
  (case name
    "arm64" :arm64
    "aarch64" :arm64
    :arm64 :arm64
    :aarch64 :arm64
    "x86_64" :x64
    "amd64" :x64
    :x64 :x64
    :x86_64 :x64
    :amd64 :x64
    (error (string "unsupported architecture: " name))))

(defn normalize-libc [operating-system name]
  (if (= operating-system :macos)
    :system
    (case name
      "musl" :musl
      :musl :musl
      "glibc" :glibc
      "gnu" :glibc
      :glibc :glibc
      :gnu :glibc
      (error (string "unsupported libc: " name)))))

(defn classify [probe]
  (def operating-system (normalize-os (get probe :os)))
  (def architecture (normalize-arch (get probe :arch)))
  @{:os operating-system
    :arch architecture
    :libc (normalize-libc operating-system (get probe :libc))})

(defn loader-paths [architecture libc]
  (case [architecture libc]
    [:arm64 :musl] ["/lib/ld-musl-aarch64.so.1"]
    [:x64 :musl] ["/lib/ld-musl-x86_64.so.1"]
    [:arm64 :glibc] ["/lib/ld-linux-aarch64.so.1"
                     "/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1"]
    [:x64 :glibc] ["/lib64/ld-linux-x86-64.so.2"
                   "/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"]
    (error "unsupported loader platform")))

(defn any-exists? [paths exists?]
  (var found? false)
  (each path paths
    (when (exists? path)
      (set found? true)))
  found?)

(defn detect-libc [architecture exists?]
  (if (any-exists? (loader-paths architecture :musl) exists?)
    :musl
    (if (any-exists? (loader-paths architecture :glibc) exists?)
      :glibc
      (error "could not detect Linux libc"))))

(defn probe [environment exists?]
  (def operating-system (normalize-os (get environment "DS_OS")))
  (def architecture (normalize-arch (get environment "DS_ARCH")))
  @{:os operating-system
    :arch architecture
    :libc (if (= operating-system :linux)
            (detect-libc architecture exists?)
            :system)})

(defn runtime-platform [platform]
  (case [(get platform :os) (get platform :arch)]
    [:macos :arm64] "macos-arm64"
    [:macos :x64] "macos-x64"
    [:linux :arm64] "linux-arm64-musl"
    [:linux :x64] "linux-x64-musl"
    (error "unsupported runtime platform")))
