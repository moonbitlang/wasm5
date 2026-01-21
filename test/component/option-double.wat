(component
  ;; Core module that doubles a value if present
  (core module $impl
    ;; double_option(discriminant, value) -> (discriminant, result)
    ;; If discriminant == 0 (None), return (0, 0)
    ;; If discriminant == 1 (Some), return (1, value * 2)
    (func $double_option (export "double_option") (param i32 i32) (result i32 i32)
      (if (result i32 i32) (i32.eqz (local.get 0))
        (then
          ;; None case: return (0, 0)
          (i32.const 0)
          (i32.const 0)
        )
        (else
          ;; Some case: return (1, value * 2)
          (i32.const 1)
          (i32.mul (local.get 1) (i32.const 2))
        )
      )
    )
  )

  (core instance $inst (instantiate $impl))

  ;; Function type: option<s32> -> option<s32>
  (type $double-option-type (func (param "value" (option s32)) (result (option s32))))

  (alias core export $inst "double_option" (core func $core-double-option))

  (func $double-option (type $double-option-type)
    (canon lift (core func $core-double-option)))

  (export "double-option" (func $double-option))
)
