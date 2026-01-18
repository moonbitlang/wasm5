(component
  ;; Import multiple functions
  (import "math:ops" (func $add (param "a" s32) (param "b" s32) (result s32)))
  (import "math:ops" (func $sub (param "a" s32) (param "b" s32) (result s32)))
  (import "math:ops" (func $mul (param "a" s32) (param "b" s32) (result s32)))

  ;; Define types
  (type $binary-op (func (param "x" s32) (param "y" s32) (result s32)))
  (type $unary-op (func (param "x" s32) (result s32)))

  ;; Core module
  (core module $m
    (import "math" "add" (func $add (param i32 i32) (result i32)))
    (import "math" "sub" (func $sub (param i32 i32) (result i32)))
    (import "math" "mul" (func $mul (param i32 i32) (result i32)))

    ;; Combined operations
    (func $add_mul (export "add-mul") (param i32 i32 i32) (result i32)
      ;; (a + b) * c
      local.get 0
      local.get 1
      call $add
      local.get 2
      call $mul
    )

    (func $square (export "square") (param i32) (result i32)
      ;; x * x
      local.get 0
      local.get 0
      call $mul
    )

    (func $diff_squared (export "diff-squared") (param i32 i32) (result i32)
      ;; (a - b) * (a - b)
      local.get 0
      local.get 1
      call $sub
      local.get 0
      local.get 1
      call $sub
      call $mul
    )
  )

  ;; Lower imported functions
  (core func $add_lowered (canon lower (func $add)))
  (core func $sub_lowered (canon lower (func $sub)))
  (core func $mul_lowered (canon lower (func $mul)))

  ;; Instantiate core module
  (core instance $i (instantiate $m
    (with "math" (instance
      (export "add" (func $add_lowered))
      (export "sub" (func $sub_lowered))
      (export "mul" (func $mul_lowered))
    ))
  ))

  ;; Alias core exports
  (alias core export $i "add-mul" (core func $add_mul))
  (alias core export $i "square" (core func $square))
  (alias core export $i "diff-squared" (core func $diff_squared))

  ;; Lift functions
  (type $ternary-op (func (param "a" s32) (param "b" s32) (param "c" s32) (result s32)))

  (func $add_mul_lifted (type $ternary-op)
    (canon lift (core func $add_mul))
  )
  (func $square_lifted (type $unary-op)
    (canon lift (core func $square))
  )
  (func $diff_squared_lifted (type $binary-op)
    (canon lift (core func $diff_squared))
  )

  ;; Export multiple functions
  (export "add-mul" (func $add_mul_lifted))
  (export "square" (func $square_lifted))
  (export "diff-squared" (func $diff_squared_lifted))
)
