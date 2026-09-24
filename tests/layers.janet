(import scripts/generated/layers :as generated)
(import scripts/lib/layers :as layers)

(def fixture (merge generated/catalog {:optional [:example] :components (merge (get generated/catalog :components) {:example {:commands ["example"] :owner :mise}})}))

(defn assert= [expected actual message]
  (unless (= expected actual)
    (error (string message ": expected " expected ", got " actual))))

(assert= true (layers/validate generated/catalog) "catalog is valid")

(def core (layers/resolve generated/catalog "core" []))
(assert= 13 (length core) "core component count")
(assert= :mise (first core) "core starts with mise")
(assert= :xh (last core) "core ends with xh")

(def remote (layers/resolve generated/catalog "remote" []))
(assert= 17 (length remote) "remote component count")
(eachp [index component] core
  (assert= component (get remote index) "remote includes core in order"))

(def optional (layers/resolve fixture "core" ["example" "example"]))
(assert= 14 (length optional) "optional components are unique")
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

(print "layers: ok")
