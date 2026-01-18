(component
  ;; Core module implementing the operations
  (core module $impl
    (func $add (export "add") (param i32 i32) (result i32)
      local.get 0
      local.get 1
      i32.add
    )
    (func $sub (export "sub") (param i32 i32) (result i32)
      local.get 0
      local.get 1
      i32.sub
    )
    (func $mul (export "mul") (param i32 i32) (result i32)
      local.get 0
      local.get 1
      i32.mul
    )
  )

  ;; Instantiate the core module
  (core instance $inst (instantiate $impl))

  ;; Define component types
  (type $add-type (func (param "a" s32) (param "b" s32) (result s32)))
  (type $sub-type (func (param "a" s32) (param "b" s32) (result s32)))
  (type $mul-type (func (param "a" s32) (param "b" s32) (result s32)))

  ;; Alias core functions
  (alias core export $inst "add" (core func $core-add))
  (alias core export $inst "sub" (core func $core-sub))
  (alias core export $inst "mul" (core func $core-mul))

  ;; Lift to component functions
  (func $add (type $add-type) (canon lift (core func $core-add)))
  (func $sub (type $sub-type) (canon lift (core func $core-sub)))
  (func $mul (type $mul-type) (canon lift (core func $core-mul)))

  ;; Export the functions
  (export "add" (func $add))
  (export "sub" (func $sub))
  (export "mul" (func $mul))
)
