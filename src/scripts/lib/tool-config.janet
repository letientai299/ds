(import scripts/lib/filesystem)
(import scripts/lib/process)
(import scripts/lib/json)

# Mise validates and normalizes the TOML first.
(defn split-toml [text separator]
  (def parts @[])
  (var start 0)
  (var index 0)
  (var quote nil)
  (var triple false)
  (var in-comment false)
  (var depth 0)
  (while (< index (length text))
    (def byte (get text index))
    (cond
      in-comment
      (when (= byte 10)
        (set in-comment false)
        (when (and (= depth 0) (= separator 10))
          (array/push parts (slice text start index))
          (set start (+ index 1))))
      quote
      (cond
        (and (= quote 34) (= byte 92)) (++ index)
        (and (= byte quote)
             (or (not triple)
                 (and (= quote (get text (+ index 1)))
                      (= quote (get text (+ index 2))))))
        (do (when triple (+= index 2)) (set quote nil)))
      (or (= byte 34) (= byte 39))
      (do
        (set quote byte)
        (set triple (and (= byte (get text (+ index 1)))
                         (= byte (get text (+ index 2)))))
        (when triple (+= index 2)))
      (= byte 35) (set in-comment true)
      (or (= byte 91) (= byte 123)) (++ depth)
      (or (= byte 93) (= byte 125)) (-- depth)
      (and (= depth 0) (= byte separator))
      (do (array/push parts (slice text start index)) (set start (+ index 1))))
    (++ index))
  (array/push parts (slice text start))
  parts)

(defn key-name [text]
  (def key (string/trim text))
  (case (get key 0)
    34 (parse key)
    39 (slice key 1 -2)
    key))

(defn tools [text]
  (def result @{})
  (var current nil)
  (each statement (split-toml text 10)
    (def line (string/trim statement))
    (unless (empty? line)
      (if (= 91 (get line 0))
        (let [array-table? (string/has-prefix? "[[" line)
              header (slice line (if array-table? 2 1) (if array-table? -3 -2))
              name (key-name (first (split-toml header 46)))]
          (set current name)
          (unless (has-key? result name) (put result name @{:blocks @""}))
          (buffer/push-string (get-in result [name :blocks])
            (if array-table? "[[tools." "[tools.") header (if array-table? "]]\n" "]\n")))
        (if current
          (buffer/push-string (get-in result [current :blocks]) statement "\n")
          (let [name (key-name (first (split-toml line 61)))]
            (put result name {:scalar (string statement "\n")}))))))
  result)

(defn read-config [mise environment file &opt key]
  (def argv @[mise "config" "get" "--file" file])
  (when key (array/push argv key))
  (def result (process/capture argv environment 30))
  (unless (= :ok (get result :state))
    (error (string "cannot read mise config: " file)))
  (get result :output))

(defn read-tools [mise environment file]
  (def contents (read-config mise environment file))
  (if (find (fn [statement]
              (def line (string/trim statement))
              (or (= line "[tools]") (string/has-prefix? "[tools." line)
                  (string/has-prefix? "[[tools." line)))
            (split-toml contents 10))
    (tools (read-config mise environment file "tools"))
    @{}))

(defn rebase-hooks [mise environment file entries]
  (def root (string/join (slice (string/split "/" file) 0 -2) "/"))
  (eachp [name entry] entries
    (when (get entry :blocks)
      (def blocks @"")
      (each statement (split-toml (get entry :blocks) 10)
        (if (and (string/has-prefix? "postinstall = " statement)
                 (string/find "{{config_root}}" statement))
          (let [command (string/trimr (read-config mise environment file
                                         (string "tools." name ".postinstall")))]
            (buffer/push-string blocks "postinstall = "
              (json/quote-string (string/replace-all "{{config_root}}" root command)) "\n"))
          (buffer/push-string blocks statement "\n")))
      (put entry :blocks blocks)))
  entries)

(defn merge-tools [contents additions]
  (def scalars (string/join (keep |(get $ :scalar) additions) ""))
  (def blocks (string/join (map |(string (get $ :blocks "")) additions) "\n"))
  (def statements (split-toml contents 10))
  (var inserted false)
  (def output @"")
  (each statement statements
    (buffer/push-string output statement "\n")
    (when (= "[tools]" (string/trim (first (string/split "#" statement))))
      (buffer/push-string output scalars)
      (set inserted true)))
  (when (and (not inserted) (not (empty? scalars)))
    (buffer/push-string output "\n[tools]\n" scalars))
  (buffer/push-string output "\n" blocks)
  (string output))

(defn identities [mise environment name]
  (def names @[name])
  (cond
    (string/has-prefix? "http:" name) (array/push names (slice name 5))
    (not (string/find ":" name))
    (let [result (process/capture [mise "registry" name] environment 10)]
      (when (= :ok (get result :state))
        (each backend (string/split " " (string/trim (get result :output)))
          (unless (empty? backend) (array/push names backend))))))
  names)

(defn seed [mise environment target sources &opt inherited]
  (def destination (if (= :link (os/lstat target :mode)) (os/realpath target) target))
  (def present (os/stat destination))
  (def contents (if present (read-config mise environment destination) ""))
  (def existing (if present (read-tools mise environment destination) @{}))
  (each file (or inherited [])
    (each name (keys (read-tools mise environment file))
      (put existing name true)))
  (each name (keys existing)
    (each alias (identities mise environment name) (put existing alias true)))
  (def additions @[])
  (each source sources
    (when (os/stat source)
      (def entries (read-tools mise environment source))
      (each name (sort (keys entries))
        (unless (or (has-key? existing name)
                    (find |(has-key? existing $) (identities mise environment name)))
          (def entry (get entries name))
          (rebase-hooks mise environment source {name entry})
          (each alias (identities mise environment name) (put existing alias true))
          (array/push additions entry)))))
  (when (or (not present) (not (empty? additions)))
    (filesystem/ensure-parent destination)
    (def pending (string destination ".ds-" (os/getpid)))
    (try
      (do
        (spit pending (merge-tools (if present (string (slurp destination)) "") additions))
        (when present (os/chmod pending (get present :permissions)))
        (try (read-config mise environment pending)
          ([_err] (spit pending (merge-tools contents additions))))
        (read-config mise environment pending)
        (os/rename pending destination))
      ([err]
        (when (os/lstat pending) (os/rm pending))
        (error err))))
  target)
