(def commands
  [{:name "shell" :group :primary :args "" :summary "Open a shell; default command"
    :details ["Use persistent trial configuration without installing packages." "Home and working directory remain unchanged."]
    :example "exec ds"}
   {:name "apply" :group :primary :args "[TARGET]" :targets :all
    :summary "Apply a layer or optional component"
    :flags ["--dry-run" "--force" "--skip"]
    :details ["Omitted targets use the saved layer, initially core."
              "--dry-run previews changes without writing."
              "--force backs up conflicts before applying."
              "Conflict policies require a layer target."
              "--skip docker skips Docker convergence for layer applications."
              "Trial configuration is separate; package installations affect the host."]
    :example "ds apply --dry-run"}
   {:name "status" :group :primary :args "[TARGET]" :targets :all
    :summary "Show health and problems"
    :flags ["--verbose" "--json" "--check"]
    :details ["Omitted targets use the saved layer, initially core."
              "--verbose includes healthy entries and Docker diagnostics."
              "--json prints the complete machine-readable report."
              "--check exits 0 when complete, 1 when unhealthy."
              "Invalid usage exits 2."]
    :example "ds status"}
   {:name "remove" :group :primary :args "TARGET" :targets :all
    :summary "Remove managed configuration; keep packages" :flags ["--dry-run"]
    :details ["Remove owned files or optional selection; restore eligible backups."
              "Packages and snapshots remain installed."
              "A target is required; --dry-run previews removal."]
    :example "ds remove core --dry-run"}
   {:name "push" :group :primary :controller true :args "HOST LAYER" :targets :layers
    :summary "Deploy over SSH; checkout only"
    :flags ["--platform" "--prefix" "--home" "--force" "--dry-run" "--deliver-only"]
    :details ["--platform NAME overrides automatic platform detection."
              "--prefix PATH sets the relative installation root."
              "--home PATH sets an isolated relative home."
              "--force backs up remote conflicts before applying."
              "--force cannot be combined with --deliver-only."
              "--dry-run delivers and stages, then previews application."
              "--deliver-only stages without application or activation."
              "Both preview modes leave the active version unchanged."]
    :example "ds push host remote --dry-run"}
   {:name "stage" :group :delivery :args "" :summary "Verify and stage a snapshot"
    :flags ["--source" "--prefix" "--manifest-sha256" "--verify-only"]
    :details ["Requires --source DIR --prefix DIR --manifest-sha256 HEX."
              "Leave the active version unchanged."]
    :example "ds stage --source ./snapshot --prefix ~/.local/share/ds --manifest-sha256 HEX"}
   {:name "activate" :group :delivery :args "VERSION" :summary "Switch to a staged snapshot"
    :flags ["--prefix" "--dry-run"]
    :details ["Atomically switch snapshots; retain the previous version."
              "--prefix DIR selects the installation root."
              "Packages and managed files are unchanged."]
    :example "ds activate ds-VERSION --dry-run"}
   {:name "rollback" :group :delivery :args "" :summary "Switch to the previous snapshot"
    :flags ["--prefix" "--dry-run"]
    :details ["--prefix DIR selects the installation root."
              "Packages and previous file changes are not rolled back."]
    :example "ds rollback --dry-run"}
   {:name "shell-init" :group :integration :args "" :summary "Print shell integration"
    :example "eval \"$(ds shell-init)\""}
   {:name "completion" :group :integration :args "bash|zsh" :values ["bash" "zsh"]
    :summary "Print shell completions" :example "source <(ds completion zsh)"}
   {:name "docker-rootful" :group :provisioning :args ""
    :summary "Provision rootful Docker with explicit approvals"
    :flags ["--approve-rootful" "--grant-docker-group"]
    :details ["Both approval flags are required, in the listed order."
              "Docker-group membership grants root-equivalent access."]
    :example "ds docker-rootful --approve-rootful --grant-docker-group"}
   {:name "adopt" :group :compatibility :args "LAYER" :targets :layers :flags ["--dry-run"]
    :summary "Back up conflicts, then apply"
    :details ["Prefer ds apply LAYER --force."] :example "ds apply core --force --dry-run"}
   {:name "force" :group :compatibility :args "LAYER" :targets :layers :flags ["--dry-run"]
    :summary "Back up conflicts, then apply"
    :details ["Prefer ds apply LAYER --force."] :example "ds apply core --force --dry-run"}
   {:name "add" :group :compatibility :args "COMPONENT" :targets :optional :flags ["--dry-run"]
    :summary "Enable an optional component"
    :details ["Prefer ds apply COMPONENT."] :example "ds apply starship"}
   {:name "unapply" :group :compatibility :args "LAYER|COMPONENT" :targets :all :flags ["--dry-run"]
    :summary "Remove managed configuration; keep packages"
    :details ["Prefer ds remove TARGET."] :example "ds remove core --dry-run"}
   {:name "diff" :group :compatibility :args "LAYER|COMPONENT" :targets :all
    :summary "Show missing, outdated, conflicting, or unavailable entries"
    :details ["Prefer ds status TARGET for problems and suggested actions."] :example "ds status core"}
   {:name "doctor" :group :compatibility :args "[LAYER|COMPONENT]" :targets :all
    :summary "Show full status and Docker diagnostics"
    :details ["Defaults to core for compatibility."
              "Prefer ds status --verbose for the saved layer."] :example "ds status remote --verbose"}
   {:name "docker" :group :compatibility :controller true :args ""
    :summary "Open the cached Ubuntu shell"
    :flags ["--rebuild" "--"]
    :details ["Prefer ds shell --docker."] :example "ds shell --docker"}])

(defn available [controller?]
  (filter |(or controller? (not (get $ :controller))) commands))

(defn specification [name controller?]
  (def spec (find |(= name (get $ :name)) (available controller?)))
  (if (and spec (= name "shell") controller?)
    (merge spec {:args "[--docker]" :flags ["--docker" "--rebuild" "--"]
                 :details (tuple ;(get spec :details)
                            "--docker opens cached Ubuntu; first use builds an image."
                            "The working directory mounts read-write at /work."
                            "--rebuild refreshes the Docker image."
                            "With --docker, pass a command after --.")})
    spec))

(defn targets [spec catalog]
  (def kind (get spec :targets))
  (tuple ;(if (find |(= kind $) [:layers :all]) (sort (keys (get catalog :layers))) [])
         ;(if (find |(= kind $) [:optional :all]) (get catalog :optional) [])))

(defn show [command catalog controller?]
  (def spec (or (specification command controller?) (error (string "unavailable command: " command))))
  (print (string "usage: ds " command
                 (if (empty? (get spec :args)) "" (string " " (get spec :args)))
                 (if (get spec :flags) " [options]" "")))
  (print (get spec :summary))
  (each line (get spec :details []) (print line))
  (when (get spec :flags)
    (print (string "options: " (string/join (get spec :flags) " "))))
  (print (string "example: " (get spec :example)))
  (when (get spec :targets)
    (print (string "targets: " (string/join (map string (targets spec catalog)) ", ")))))

(defn usage [emit catalog controller? all?]
  (emit "ds - manage your shell environment")
  (emit "usage: ds [command]")
  (each group (if all? [:primary :delivery :integration :provisioning :compatibility] [:primary])
    (emit "")
    (emit (string (if (= group :primary) "commands" group) ":"))
    (each item (available controller?)
      (when (= group (get item :group))
        (def spec (specification (get item :name) controller?))
        (emit (string/format "  %-24s %s"
                (string (get spec :name) " " (get spec :args)) (get spec :summary))))))
  (each line ["" "examples:" "  ds" "  ds apply --dry-run" "  ds apply" ""
              (string "layers: " (string/join (map string (sort (keys (get catalog :layers)))) ", "))
              "remote is an extended local preset, not an SSH destination."
              (string "optional components: " (string/join (map string (get catalog :optional)) ", "))
              "Omitted targets use the saved layer, initially core."
              "Use ds COMMAND --help for options."
              "Use ds help --all for advanced commands."]
    (emit line)))

(defn complete [shell catalog controller?]
  (unless (find |(= $ shell) ["bash" "zsh"]) (error "completion requires bash or zsh"))
  (def specs (map |(specification (get $ :name) controller?) (available controller?)))
  (def names (string/join (map |(get $ :name) specs) " "))
  (def primary (string/join (map |(get $ :name) (filter |(= :primary (get $ :group)) specs)) " "))
  (print "_ds_complete() {")
  (if (= shell "bash")
    (print "  local cmd=${COMP_WORDS[1]} cur=${COMP_WORDS[COMP_CWORD]} pos=$COMP_CWORD prev=${COMP_WORDS[COMP_CWORD-1]} choices")
    (print "  local cmd=$words[2] cur=$words[CURRENT] pos=$((CURRENT-1)) prev=$words[CURRENT-1] choices"))
  (if (= shell "bash")
    (print "  local i; for ((i=2; i<COMP_CWORD; i++)); do [ \"${COMP_WORDS[i]}\" != -- ] || { COMPREPLY=(); return; }; done")
    (print "  local i; for ((i=3; i<CURRENT; i++)); do [ \"${words[i]}\" != -- ] || return; done"))
  (print (string "  choices='" primary " help --help'"))
  (print (string "  [ -z \"$cur\" ] || choices='" names " help --help'"))
  (print "  if [ \"$pos\" -gt 1 ]; then")
  (print "    case \"$cmd\" in")
  (each spec specs
    (def choices (tuple ;(map string (targets spec catalog)) ;(get spec :flags []) ;(get spec :values []) "--help"))
    (print (string "      " (get spec :name) ") choices='" (string/join choices " ") "' ;;")))
  (print (string "      help) choices='" names " --all' ;;"))
  (print "      *) choices='--help' ;;")
  (print "    esac")
  (print "    [ \"$prev\" != --skip ] || choices=docker")
  (print "  fi")
  (if (= shell "bash")
    (print "  COMPREPLY=(); while IFS= read -r item; do COMPREPLY+=(\"$item\"); done < <(compgen -W \"$choices\" -- \"$cur\")")
    (print "  compadd -- ${=choices}"))
  (print "}")
  (print (if (= shell "bash") "complete -F _ds_complete ds" "compdef _ds_complete ds")))
