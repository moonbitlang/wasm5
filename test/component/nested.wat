(component
  ;; Nested inner component
  (component $inner
    ;; Core module inside inner component
    (core module $m
      (func $double (export "double") (param i32) (result i32)
        local.get 0
        i32.const 2
        i32.mul
      )
    )

    ;; Instantiate core module
    (core instance $i (instantiate $m))

    ;; Define function type
    (type $double-type (func (param "x" s32) (result s32)))

    ;; Alias and lift
    (alias core export $i "double" (core func $double))
    (func $double_lifted (type $double-type)
      (canon lift (core func $double))
    )

    ;; Export from inner component
    (export "double" (func $double_lifted))
  )

  ;; Instantiate the inner component
  (instance $inner_inst (instantiate $inner))

  ;; Alias the export from inner instance
  (alias export $inner_inst "double" (func $double))

  ;; Define outer function type
  (type $quadruple-type (func (param "x" s32) (result s32)))

  ;; Core module that uses the inner component's function
  (core module $outer_m
    (import "inner" "double" (func $double (param i32) (result i32)))

    (func $quadruple (export "quadruple") (param i32) (result i32)
      ;; quadruple(x) = double(double(x))
      local.get 0
      call $double
      call $double
    )
  )

  ;; Lower the aliased function for core use
  (core func $double_lowered (canon lower (func $double)))

  ;; Instantiate outer core module
  (core instance $outer_i (instantiate $outer_m
    (with "inner" (instance
      (export "double" (func $double_lowered))
    ))
  ))

  ;; Alias and lift quadruple
  (alias core export $outer_i "quadruple" (core func $quadruple))
  (func $quadruple_lifted (type $quadruple-type)
    (canon lift (core func $quadruple))
  )

  ;; Export from outer component
  (export "quadruple" (func $quadruple_lifted))
)
