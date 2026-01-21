(component
  ;; Outer component that composes an inner component

  ;; Inner component: provides an "add" function
  (component $inner
    (core module $impl
      (func $add (export "add") (param i32 i32) (result i32)
        (i32.add (local.get 0) (local.get 1))
      )
    )

    (core instance $inst (instantiate $impl))

    (type $add-type (func (param "a" s32) (param "b" s32) (result s32)))

    (alias core export $inst "add" (core func $core-add))

    (func $add (type $add-type)
      (canon lift (core func $core-add)))

    (export "add" (func $add))
  )

  ;; Instantiate the inner component
  (instance $inner-inst (instantiate $inner))

  ;; Alias the add function from the inner instance
  (alias export $inner-inst "add" (func $aliased-add))

  ;; Core module that uses the aliased add function
  (core module $outer-impl
    (import "math" "add" (func $imported-add (param i32 i32) (result i32)))

    ;; double_add(a, b) = add(a, b) + add(a, b) = 2 * (a + b)
    (func $double_add (export "double_add") (param i32 i32) (result i32)
      (i32.add
        (call $imported-add (local.get 0) (local.get 1))
        (call $imported-add (local.get 0) (local.get 1))
      )
    )
  )

  ;; Lower the aliased add function for the core module
  (core func $lowered-add (canon lower (func $aliased-add)))

  ;; Create a virtual core instance with the lowered function
  (core instance $math-exports (export "add" (func $lowered-add)))

  ;; Instantiate the outer core module with the math imports
  (core instance $outer-inst (instantiate $outer-impl
    (with "math" (instance $math-exports))
  ))

  ;; Type for the exported function
  (type $double-add-type (func (param "a" s32) (param "b" s32) (result s32)))

  ;; Alias and lift the double_add function
  (alias core export $outer-inst "double_add" (core func $core-double-add))

  (func $double-add (type $double-add-type)
    (canon lift (core func $core-double-add)))

  ;; Export the composed function
  (export "double-add" (func $double-add))
)
