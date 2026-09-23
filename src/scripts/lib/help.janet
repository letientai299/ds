(def commands
  {"status" ["LAYER|COMPONENT [--json] [--check]" "Report pinned versions and file health. --check: 0 complete, 1 unhealthy; invalid usage: 2." "ds status remote --json --check"]
   "diff" ["LAYER|COMPONENT" "Show missing, outdated, conflicting, or unavailable entries." "ds diff core"]
   "doctor" ["[LAYER|COMPONENT]" "Report status and bounded Docker diagnostics; defaults to core." "ds doctor remote"]
   "apply" ["LAYER [--dry-run] [--skip docker]" "Install packages, write managed files, then activate. Conflicts stop execution." "ds adopt core --dry-run"]
   "adopt" ["LAYER [--dry-run]" "Back up conflicts to .ds-adopted, then apply. Existing backups block execution." "ds adopt core --dry-run"]
   "force" ["LAYER [--dry-run]" "Replace conflicts without backups, then apply. User content outside RC markers survives." "ds force core --dry-run"]
   "unapply" ["LAYER|COMPONENT [--dry-run]" "Remove owned files or selection; restore eligible backups. Packages remain installed." "ds unapply core --dry-run"]
   "add" ["COMPONENT [--dry-run]" "Install and select an optional component." "ds add starship --dry-run"]
   "stage" ["--source DIR --prefix DIR --manifest-sha256 HEX [--verify-only]" "Verify and stage a snapshot. Leave current unchanged." "ds stage --source ./snapshot --prefix ~/.local/share/ds --manifest-sha256 HEX"]
   "activate" ["VERSION [--prefix DIR] [--dry-run]" "Atomically switch current to a staged version; retain previous. Packages and files are unchanged." "ds activate ds-VERSION --dry-run"]
   "rollback" ["[--prefix DIR] [--dry-run]" "Switch current to previous; packages and managed-file contents are not rolled back." "ds rollback --dry-run"]
   "completion" ["bash|zsh" "Print shell completion using this catalog." "source <(ds completion zsh)"]
   "shell" ["" "Try core in Zsh without applying dotfiles or packages." "exec ds shell"]
   "shell-init" ["" "Print shell integration." "eval \"$(ds shell-init)\""]
   "docker" ["[--rebuild] [-- COMMAND [ARG...]]" "Cached Ubuntu core shell; current directory mounts at /work." "ds docker"]
   "docker-rootful" ["--approve-rootful --grant-docker-group" "Provision rootful Docker and grant root-equivalent group access." "ds docker-rootful --approve-rootful --grant-docker-group"]
   "push" ["HOST LAYER [--platform NAME] [--prefix PATH] [--home PATH] [--dry-run|--deliver-only]" "Deliver from a checkout, then apply or preview. Deliver-only leaves current unchanged." "ds push host core --dry-run"]})

(defn show [command catalog]
  (def spec (or (get commands command) (error (string "unknown command: " command))))
  (print (string "usage: ds " command " " (get spec 0)))
  (print (get spec 1))
  (print (string "example: " (get spec 2)))
  (print (string "layers: " (string/join (map string (sort (keys (get catalog :layers)))) ", ")))
  (print (string "optional: " (string/join (map string (get catalog :optional)) ", "))))

(defn complete [shell catalog controller?]
  (unless (find |(= $ shell) ["bash" "zsh"]) (error "completion requires bash or zsh"))
  (def names (string/join (sort (filter (fn [name]
                                        (or controller? (not (find |(= $ name) ["push" "docker"]))))
                                      (keys commands))) " "))
  (def layers (string/join (map string (sort (keys (get catalog :layers)))) " "))
  (def optional (string/join (map string (get catalog :optional)) " "))
  (print "_ds_complete() {")
  (if (= shell "bash")
    (print "  local cmd=${COMP_WORDS[1]} cur=${COMP_WORDS[COMP_CWORD]} pos=$COMP_CWORD choices")
    (print "  local cmd=$words[2] cur=$words[CURRENT] pos=$((CURRENT-1)) choices"))
  (print (string "  choices='" names " help --help'"))
  (print "  if [ \"$pos\" -gt 1 ]; then")
  (print "    case \"$cmd\" in")
  (print (string "      status) choices='" layers " " optional " --json --check --help' ;;"))
  (print (string "      diff|doctor|unapply) choices='" layers " " optional " --help'; [ \"$cmd\" != unapply ] || choices=\"$choices --dry-run\" ;;"))
  (print (string "      apply) choices='" layers " --dry-run --skip docker --help' ;;"))
  (print (string "      adopt|force) choices='" layers " --dry-run --help' ;;"))
  (print (string "      add) choices='" optional " --dry-run --help' ;;"))
  (print "      completion) choices='bash zsh --help' ;;")
  (print "      docker) choices='--rebuild --help --' ;;")
  (print "      activate|rollback) choices='--prefix --dry-run --help' ;;")
  (print "      stage) choices='--source --prefix --manifest-sha256 --verify-only --help' ;;")
  (print (string "      push) choices='" layers " --platform --prefix --home --dry-run --deliver-only --help' ;;"))
  (print "      docker-rootful) choices='--approve-rootful --grant-docker-group --help' ;;")
  (print (string "      help) choices='" names "' ;;"))
  (print "      *) choices='--help' ;;")
  (print "    esac")
  (print "  fi")
  (if (= shell "bash")
    (print "  COMPREPLY=(); while IFS= read -r item; do COMPREPLY+=(\"$item\"); done < <(compgen -W \"$choices\" -- \"$cur\")")
    (print "  compadd -- ${=choices}"))
  (print "}")
  (print (if (= shell "bash") "complete -F _ds_complete ds" "compdef _ds_complete ds")))
