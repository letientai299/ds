(import scripts/lib/upgrade)

(defn assert= [expected actual message]
  (unless (= expected actual)
    (error (string message ": expected " expected ", got " actual))))

(def base {"HOME" "/isolated/home" "DS_OS" "Linux" "DS_ARCH" "x86_64"
           "DS_UID" "1000" "DS_MISE" "/isolated/mise"})
(defn probe [commands]
  (fn [command] (not= nil (find |(= $ command) commands))))
(each [commands expected] [[[] nil]
                           [["apt-get" "dnf"] [["apt-get" "update"] ["apt-get" "upgrade" "-y" "-o" "Dpkg::Options::=--force-confdef"
                                               "-o" "Dpkg::Options::=--force-confold"]]]
                           [["dnf" "yum"] [["dnf" "upgrade" "-y"]]]
                           [["yum"] [["yum" "update" "-y"]]]
                           [["apk"] [["apk" "update"] ["apk" "upgrade"]]]]
  (assert= expected (upgrade/native-commands base (probe commands)) "manager selection"))
(assert= nil (upgrade/native-commands (merge base {"DS_OS" "Darwin"}) (probe ["apt-get"]))
         "macOS skips Linux managers")

(def calls @[])
(def messages @[])
(var failure nil)
(defn runner [argv environment]
  (assert= "" (string (or (file/read (get environment :in) :all) "")) "subprocess input closed")
  (array/push calls [(tuple ;argv) environment])
  (if (= failure (tuple ;argv)) 1 0))
(defn emit [message] (array/push messages message))
(defn invoke [environment commands]
  (array/clear calls)
  (array/clear messages)
  (upgrade/run "/snapshot" environment (probe commands) runner emit))

(assert= 0 (invoke base ["apt-get" "brew" "nvim"]) "all stages succeed")
(assert= [["sh" "/snapshot/src/scripts/pull-configs.sh"]
          ["sudo" "-n" "env" "DEBIAN_FRONTEND=noninteractive" "NEEDRESTART_MODE=a" "apt-get" "update"] ["sudo" "-n" "env" "DEBIAN_FRONTEND=noninteractive" "NEEDRESTART_MODE=a" "apt-get" "upgrade" "-y"
           "-o" "Dpkg::Options::=--force-confdef" "-o" "Dpkg::Options::=--force-confold"]
          ["brew" "update"] ["brew" "upgrade" "--no-ask"]
          ["/isolated/mise" "-C" "/" "plugins" "update" "--yes"]
          ["/isolated/mise" "-C" "/" "upgrade" "--bump" "--no-prune" "--yes"]
          ["nvim" "--headless" upgrade/neovim-command "+qa"]]
         (tuple ;(map |(get $ 0) calls)) "upgrade order")
(assert= "1" (get-in calls [3 1 "NONINTERACTIVE"]) "Homebrew installer confirmations")
(assert= "1" (get-in calls [3 1 "HOMEBREW_NO_ASK"]) "Homebrew upgrade confirmations")
(assert= "noninteractive" (get-in calls [1 1 "DEBIAN_FRONTEND"]) "Debian confirmations")
(assert= "a" (get-in calls [1 1 "NEEDRESTART_MODE"]) "service restart confirmations")
(assert= "0" (get-in calls [0 1 "GIT_TERMINAL_PROMPT"]) "Git terminal prompts")
(assert= nil (get base "DEBIAN_FRONTEND") "caller environment preserved")
(assert= "1" (get-in calls [6 1 "MISE_YES"]) "mise confirmations")
(assert= "0s" (get-in calls [6 1 "MISE_MINIMUM_RELEASE_AGE"]) "latest releases enabled")
(assert= "/isolated/home/.config/mise/config.toml"
         (get-in calls [6 1 "MISE_GLOBAL_CONFIG_FILE"]) "global tools")
(assert= nil (get-in calls [6 1 "MISE_GLOBAL_CONFIG_ROOT"]) "no payload overrides")

(def custom (merge base {"MISE_GLOBAL_CONFIG_FILE" "/custom/tools.toml"
                        "MISE_CONFIG_DIR" "/custom/config" "MISE_ENV" "personal"
                        "MISE_MINIMUM_RELEASE_AGE" "24h"
                        "XDG_CONFIG_HOME" "/trial/config"}))
(assert= 0 (invoke custom []) "missing optional managers")
(assert= 3 (length calls) "mise runs without native managers")
(assert= "/custom/tools.toml" (get-in calls [2 1 "MISE_GLOBAL_CONFIG_FILE"]) "custom global")
(assert= "/custom/config" (get-in calls [2 1 "MISE_CONFIG_DIR"]) "custom config directory")
(assert= "personal" (get-in calls [2 1 "MISE_ENV"]) "active global profile")
(assert= "0s" (get-in calls [2 1 "MISE_MINIMUM_RELEASE_AGE"]) "release delay overridden")
(assert= 0 (invoke (merge base {"DS_UID" "0"}) ["apk"]) "root upgrade")
(assert= ["apk" "update"] (get-in calls [1 0]) "root skips sudo")

(set failure ["sudo" "-n" "env" "DEBIAN_FRONTEND=noninteractive" "NEEDRESTART_MODE=a" "apt-get" "update"])
(assert= 1 (invoke base ["apt-get" "brew"]) "failure returned")
(assert= 6 (length calls) "dependent command skipped")
(assert= ["brew" "update"] (get-in calls [2 0]) "independent manager continues")
(set failure ["/isolated/mise" "-C" "/" "upgrade" "--bump" "--no-prune" "--yes"])
(assert= 1 (invoke base ["nvim"]) "tool failure returned")
(assert= "nvim" (get-in calls [3 0 0]) "Neovim continues")
(assert= 1 (upgrade/run-stage "missing" [["missing"]]
                             (fn [_argv _environment] (error "missing executable")) base emit)
         "spawn failure returned")
(set failure ["sh" "/snapshot/src/scripts/pull-configs.sh"])
(assert= 1 (invoke base ["apt-get" "brew" "nvim"]) "pull failure returned")
(assert= 1 (length calls) "pull failure prevents software upgrades")
(assert= 0 (upgrade/run-stage "closed input"
                             [["/bin/sh" "-c" "if read -r answer; then exit 1; fi"]]
                             (fn [argv environment] (os/execute argv :pe environment)) {} emit)
         "child process cannot request terminal input")
(print "upgrade: ok")
