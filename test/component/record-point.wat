(component
  ;; Core module that works with a point record (flattened to x, y)
  (core module $impl
    ;; distance_squared(x, y) -> x*x + y*y
    (func $distance_squared (export "distance_squared") (param i32 i32) (result i32)
      (i32.add
        (i32.mul (local.get 0) (local.get 0))
        (i32.mul (local.get 1) (local.get 1)))
    )

    ;; add_points(x1, y1, x2, y2) -> (x1+x2, y1+y2)
    (func $add_points (export "add_points") (param i32 i32 i32 i32) (result i32 i32)
      (i32.add (local.get 0) (local.get 2))
      (i32.add (local.get 1) (local.get 3))
    )
  )

  (core instance $inst (instantiate $impl))

  ;; Function types with inline record
  (type $distance-squared-type (func (param "p" (record (field "x" s32) (field "y" s32))) (result s32)))
  (type $add-points-type (func
    (param "p1" (record (field "x" s32) (field "y" s32)))
    (param "p2" (record (field "x" s32) (field "y" s32)))
    (result (record (field "x" s32) (field "y" s32)))))

  (alias core export $inst "distance_squared" (core func $core-distance-squared))
  (alias core export $inst "add_points" (core func $core-add-points))

  ;; Lift functions (no memory needed for flat records)
  (func $distance-squared (type $distance-squared-type)
    (canon lift (core func $core-distance-squared)))

  (func $add-points (type $add-points-type)
    (canon lift (core func $core-add-points)))

  (export "distance-squared" (func $distance-squared))
  (export "add-points" (func $add-points))
)
