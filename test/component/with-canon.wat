(component
  ;; Core module with add function
  (core module $m
    (func $add (export "add") (param i32 i32) (result i32)
      local.get 0
      local.get 1
      i32.add
    )
    (memory (export "memory") 1)
  )

  ;; Instantiate the core module
  (core instance $i (instantiate $m))

  ;; Define the component function type
  (type $add-type (func (param "a" s32) (param "b" s32) (result s32)))

  ;; Lift the core function to component function
  (func $add (type $add-type)
    (canon lift (core func $i "add"))
  )

  ;; Export the component function
  (export "add" (func $add))
)
