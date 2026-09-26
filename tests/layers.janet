(import scripts/generated/layers :as generated)
(import scripts/lib/layers :as layers)
(import scripts/lib/help)

(def fixture (merge generated/catalog {:optional [:example] :components (merge (get generated/catalog :components) {:example {:commands ["example"] :owner :mise}})}))

(defn assert= [expected actual message]
  (unless (= expected actual)
    (error (string message ": expected " expected ", got " actual))))

(assert= true (layers/validate generated/catalog) "catalog is valid")

(def core (layers/resolve generated/catalog "core" []))
(assert= 12 (length core) "core component count")
(assert= :mise (first core) "core starts with mise")
(assert= :xh (last core) "core ends with xh")

(def remote (layers/resolve generated/catalog "remote" []))
(assert= 15 (length remote) "remote component count")
(eachp [index component] core
  (assert= component (get remote index) "remote includes core in order"))

(assert= [:bat :delta :worktrunk :gokill :eza :gdu :ouch] (tuple/slice (layers/resolve generated/catalog "extra" [])) "extra is independent")
(assert= [:kitty] (tuple/slice (layers/resolve generated/catalog "ui" [])) "ui is independent")
(def all-components (layers/resolve generated/catalog "all" []))
(each name ["core" "remote" "extra" "ui"]
  (each component (layers/resolve generated/catalog name [])
    (unless (find |(= $ component) all-components)
      (error (string "all is missing " component)))))
(assert= 23 (length all-components) "all deduplicates components")

(def optional (layers/resolve fixture "core" ["example" "example"]))
(assert= 13 (length optional) "optional components are unique")
(assert= :example (last optional) "optional component is appended")
(assert= true (layers/optional-component? fixture :example) "example is optional")

(var unknown-failed? false)
(try
  (layers/resolve generated/catalog "core" ["git"])
  ([_err] (set unknown-failed? true)))
(unless unknown-failed?
  (error "non-optional component should fail"))

(def duplicate-owner-catalog
  @{:layers {:core [:first :second]}
    :components
    {:first {:commands ["same"]}
     :second {:commands ["same"]}}})
(var duplicate-owner-failed? false)
(try
  (layers/validate duplicate-owner-catalog)
  ([_err] (set duplicate-owner-failed? true)))
(unless duplicate-owner-failed?
  (error "duplicate command ownership should fail"))

(def help-lines @[])
(help/usage |(array/push help-lines $)
  {:layers {:core [:one :two] :remote [:one :two :three] :sample [:four]} :optional [:extra]}
  true true)
(each line ["  core: one, two" "  remote: core tools, plus three" "  sample: four" "  optional (any layer): extra"]
  (unless (find |(= $ line) help-lines) (error (string "catalog help missing: " line))))
(each command ["adopt" "force" "unapply"]
  (assert= nil (help/specification command true) "removed command is unavailable"))

(print "layers: ok")
