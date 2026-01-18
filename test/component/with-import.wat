(component
  ;; Import a simple function (no string params to avoid memory requirements)
  (import "host:math" (func $add (param "a" s32) (param "b" s32) (result s32)))

  ;; Define the component function type for the export
  (type $compute-type (func (param "x" s32) (result s32)))

  ;; Core module
  (core module $m
    (import "host" "add" (func $host_add (param i32 i32) (result i32)))
    (memory (export "memory") 1)

    (func $compute (export "compute") (param i32) (result i32)
      ;; compute(x) = add(x, 10)
      local.get 0
      i32.const 10
      call $host_add
    )
  )

  ;; Lower the imported component function to core function
  (core func $add_lowered (canon lower (func $add)))

  ;; Instantiate core module with the lowered import
  (core instance $i (instantiate $m
    (with "host" (instance
      (export "add" (func $add_lowered))
    ))
  ))

  ;; Alias exports from the core instance
  (alias core export $i "compute" (core func $compute))

  ;; Lift the compute function
  (func $compute_lifted (type $compute-type)
    (canon lift (core func $compute))
  )

  ;; Export
  (export "compute" (func $compute_lifted))
)
