(import scripts/lib/filesystem)

(defn prefix [root]
  (def parts (string/split "/" root))
  (when (= "versions" (get parts (- (length parts) 2)))
    (string/join (slice parts 0 (- (length parts) 2)) "/")))

(defn version-name [name]
  (unless (and (string? name) (> (length name) 0)
               (not (string/has-prefix? "." name))
               (peg/match ~(* (some (+ (range "az" "AZ" "09") "." "_" "-")) -1) name))
    (error "invalid version name"))
  name)

(defn candidate [base name]
  (def path (string base "/versions/" (version-name name)))
  (unless (and (= :directory (os/lstat path :mode)) (= :file (os/stat (string path "/ds") :mode))
               (string/find "x" (os/stat (string path "/ds") :permissions)))
    (error (string "staged version is unavailable: " name)))
  path)

(defn link-version [base name]
  (def link (string base "/" name))
  (when (os/lstat link)
    (unless (= :link (os/lstat link :mode))
      (error (string "activation path is not a symlink: " link)))
    (def target (os/readlink link))
    (unless (string/has-prefix? "versions/" target)
      (error (string "invalid activation link: " link)))
    (version-name (slice target 9))))

(defn replace-link [base name version]
  (def temporary (string base "/." name "." (os/getpid)))
  (when (os/lstat temporary) (error (string "temporary link exists: " temporary)))
  (os/link (string "versions/" version) temporary true)
  (try
    (os/rename temporary (string base "/" name))
    ([err] (os/rm temporary) (error err))))

(defn activate [root]
  (def base (prefix root))
  (unless base (error "activation requires a staged version"))
  (def next (version-name (last (string/split "/" root))))
  (candidate base next)
  (def old (link-version base "current"))
  (link-version base "previous")
  (unless (= old next)
    (when old (replace-link base "previous" old))
    (replace-link base "current" next)))

(defn with-lock [base operation]
  (def lock (string base "/.mutation-lock"))
  (filesystem/ensure-parent lock)
  (unless (os/mkdir lock) (error (string "installation busy: " lock)))
  (try
    (do (def result (operation)) (os/rmdir lock) result)
    ([err] (os/rmdir lock) (error err))))
