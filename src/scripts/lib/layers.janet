(defn layer-components
  [catalog layer-name]
  (def layer (get (get catalog :layers) (keyword layer-name)))
  (if layer
    layer
    (error (string "unknown layer: " layer-name))))

(defn known-layer?
  [catalog layer-name]
  (not= nil (get (get catalog :layers) (keyword layer-name))))

(defn known-component?
  [catalog component]
  (has-key? (get catalog :components) component))

(defn optional-component?
  [catalog component]
  (not= nil (find |(= $ component) (get catalog :optional))))

(defn validate-layer
  [catalog layer-name components]
  (def seen @{})
  (each component components
    (unless (known-component? catalog component)
      (error (string "layer " layer-name " references unknown component: " component)))
    (when (has-key? seen component)
      (error (string "layer " layer-name " contains duplicate component: " component)))
    (put seen component true)))

(defn validate-command-owners
  [catalog]
  (def owners @{})
  (eachp [component spec] (get catalog :components)
    (each command (get spec :commands)
      (when (has-key? owners command)
        (error (string "duplicate command owner: " command)))
      (put owners command component))))

(defn validate
  [catalog]
  (eachp [layer-name components] (get catalog :layers)
    (validate-layer catalog layer-name components))
  (validate-layer catalog :optional (get catalog :optional))
  (validate-command-owners catalog)
  true)

(defn append-unique
  [items item]
  (if (find (fn [candidate] (= candidate item)) items)
    items
    (do
      (array/push items item)
      items)))

(defn resolve
  [catalog layer-name extras]
  (def resolved @[])
  (each component (layer-components catalog layer-name)
    (append-unique resolved component))
  (each extra extras
    (def component (keyword extra))
    (unless (optional-component? catalog component)
      (error (string "unknown optional component: " extra)))
    (append-unique resolved component))
  resolved)
