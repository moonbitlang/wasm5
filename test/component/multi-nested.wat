(component
  ;; Component with multiple nested components
  ;; inner-add provides add, inner-mul provides mul
  ;; outer uses both to compute (a + b) * (a - b) = a^2 - b^2

  ;; Inner component 1: provides add function
  (component $adder
    (core module $impl
      (func $add (export "add") (param i32 i32) (result i32)
        (i32.add (local.get 0) (local.get 1))
      )
    )
    (core instance $inst (instantiate $impl))
    (type $binop-type (func (param "a" s32) (param "b" s32) (result s32)))
    (alias core export $inst "add" (core func $core-add))
    (func $add (type $binop-type) (canon lift (core func $core-add)))
    (export "add" (func $add))
  )

  ;; Inner component 2: provides sub function
  (component $subber
    (core module $impl
      (func $sub (export "sub") (param i32 i32) (result i32)
        (i32.sub (local.get 0) (local.get 1))
      )
    )
    (core instance $inst (instantiate $impl))
    (type $binop-type (func (param "a" s32) (param "b" s32) (result s32)))
    (alias core export $inst "sub" (core func $core-sub))
    (func $sub (type $binop-type) (canon lift (core func $core-sub)))
    (export "sub" (func $sub))
  )

  ;; Inner component 3: provides mul function
  (component $multiplier
    (core module $impl
      (func $mul (export "mul") (param i32 i32) (result i32)
        (i32.mul (local.get 0) (local.get 1))
      )
    )
    (core instance $inst (instantiate $impl))
    (type $binop-type (func (param "a" s32) (param "b" s32) (result s32)))
    (alias core export $inst "mul" (core func $core-mul))
    (func $mul (type $binop-type) (canon lift (core func $core-mul)))
    (export "mul" (func $mul))
  )

  ;; Instantiate all inner components
  (instance $add-inst (instantiate $adder))
  (instance $sub-inst (instantiate $subber))
  (instance $mul-inst (instantiate $multiplier))

  ;; Alias functions from instances
  (alias export $add-inst "add" (func $add-fn))
  (alias export $sub-inst "sub" (func $sub-fn))
  (alias export $mul-inst "mul" (func $mul-fn))

  ;; Core module that computes difference of squares: (a+b) * (a-b)
  (core module $outer-impl
    (import "ops" "add" (func $add (param i32 i32) (result i32)))
    (import "ops" "sub" (func $sub (param i32 i32) (result i32)))
    (import "ops" "mul" (func $mul (param i32 i32) (result i32)))

    ;; diff_squares(a, b) = (a + b) * (a - b) = a^2 - b^2
    (func $diff_squares (export "diff_squares") (param i32 i32) (result i32)
      (call $mul
        (call $add (local.get 0) (local.get 1))
        (call $sub (local.get 0) (local.get 1))
      )
    )
  )

  ;; Lower functions for core module
  (core func $low-add (canon lower (func $add-fn)))
  (core func $low-sub (canon lower (func $sub-fn)))
  (core func $low-mul (canon lower (func $mul-fn)))

  ;; Create virtual core instance with all lowered functions
  (core instance $ops-exports
    (export "add" (func $low-add))
    (export "sub" (func $low-sub))
    (export "mul" (func $low-mul))
  )

  ;; Instantiate outer core module
  (core instance $outer-inst (instantiate $outer-impl
    (with "ops" (instance $ops-exports))
  ))

  ;; Type and lift the result
  (type $diff-type (func (param "a" s32) (param "b" s32) (result s32)))
  (alias core export $outer-inst "diff_squares" (core func $core-diff))
  (func $diff-squares (type $diff-type) (canon lift (core func $core-diff)))

  ;; Export
  (export "diff-squares" (func $diff-squares))
)
