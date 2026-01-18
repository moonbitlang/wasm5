(component
  ;; Core module with initialization function
  (core module $m
    (global $initialized (mut i32) (i32.const 0))

    (func $init (export "init")
      ;; Set initialized flag to 1
      i32.const 1
      global.set $initialized
    )

    (func $is_initialized (export "is-initialized") (result i32)
      global.get $initialized
    )
  )

  ;; Instantiate core module
  (core instance $i (instantiate $m))

  ;; Define function types
  (type $init-type (func))
  (type $check-type (func (result s32)))

  ;; Alias core functions
  (alias core export $i "init" (core func $init))
  (alias core export $i "is-initialized" (core func $is_initialized))

  ;; Lift functions
  (func $init_lifted (type $init-type)
    (canon lift (core func $init))
  )
  (func $check_lifted (type $check-type)
    (canon lift (core func $is_initialized))
  )

  ;; Start section - call init on component instantiation
  (start $init_lifted)

  ;; Export the check function
  (export "is-initialized" (func $check_lifted))
)
