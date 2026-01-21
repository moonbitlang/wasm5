(component
  ;; Core module that divides two numbers, returning error on divide by zero
  (core module $impl
    ;; safe_divide(a, b) -> (discriminant, value)
    ;; If b == 0, return (1, 0) for Err
    ;; Otherwise, return (0, a/b) for Ok
    (func $safe_divide (export "safe_divide") (param i32 i32) (result i32 i32)
      (if (result i32 i32) (i32.eqz (local.get 1))
        (then
          ;; Division by zero: return Err (discriminant 1)
          (i32.const 1)
          (i32.const 0)  ;; error code or placeholder
        )
        (else
          ;; Success: return Ok (discriminant 0)
          (i32.const 0)
          (i32.div_s (local.get 0) (local.get 1))
        )
      )
    )
  )

  (core instance $inst (instantiate $impl))

  ;; Function type: (s32, s32) -> result<s32, s32>
  (type $safe-divide-type (func (param "a" s32) (param "b" s32) (result (result s32 (error s32)))))

  (alias core export $inst "safe_divide" (core func $core-safe-divide))

  (func $safe-divide (type $safe-divide-type)
    (canon lift (core func $core-safe-divide)))

  (export "safe-divide" (func $safe-divide))
)
