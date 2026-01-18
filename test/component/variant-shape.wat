(component
  ;; Core module that calculates area of shapes
  ;; Variant: circle(radius) | rectangle(width, height)
  ;; Flattened: (discriminant, field1, field2)
  ;; circle: (0, radius, 0)
  ;; rectangle: (1, width, height)
  (core module $impl
    ;; area(discriminant, field1, field2) -> area
    (func $area (export "area") (param i32 i32 i32) (result i32)
      (if (result i32) (i32.eqz (local.get 0))
        (then
          ;; Circle: area = radius * radius * 3 (approximation)
          (i32.mul
            (i32.mul (local.get 1) (local.get 1))
            (i32.const 3)
          )
        )
        (else
          ;; Rectangle: area = width * height
          (i32.mul (local.get 1) (local.get 2))
        )
      )
    )
  )

  (core instance $inst (instantiate $impl))

  ;; Variant type for shape
  (type $shape (variant (case "circle" s32) (case "rectangle" (tuple s32 s32))))
  (type $area-type (func (param "shape" $shape) (result s32)))

  (alias core export $inst "area" (core func $core-area))

  (func $area (type $area-type)
    (canon lift (core func $core-area)))

  (export "area" (func $area))
)
