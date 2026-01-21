(component
  ;; Define a type at outer scope
  (type $add-type (func (param "a" s32) (param "b" s32) (result s32)))

  ;; Nested component that uses outer type via alias
  (component $inner
    ;; Alias the type from outer scope (outer 1 = parent component, type 0)
    (alias outer 1 type 0 (type $outer-add-type))

    ;; Core module
    (core module $m
      (func $add (export "add") (param i32 i32) (result i32)
        local.get 0
        local.get 1
        i32.add
      )
    )

    ;; Instantiate and lift
    (core instance $i (instantiate $m))
    (alias core export $i "add" (core func $add))

    ;; Use the aliased outer type
    (func $add_fn (type $outer-add-type)
      (canon lift (core func $add))
    )

    (export "add" (func $add_fn))
  )

  ;; Instantiate inner component
  (instance $inner_inst (instantiate $inner))

  ;; Export from inner
  (export "add" (func $inner_inst "add"))
)
