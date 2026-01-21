(component
  ;; A simple resource-based counter component
  ;; Resource type: Counter (holds a count value as i32 rep)

  ;; Core module that manages counter operations
  (core module $impl
    (memory (export "mem") 1)

    ;; Simple counter operations
    ;; create: () -> rep (i32)
    (func $create (export "create") (result i32)
      (i32.const 0)  ;; initial count is 0
    )

    ;; get: (rep: i32) -> count: i32
    (func $get (export "get") (param i32) (result i32)
      (local.get 0)  ;; rep is the count itself
    )

    ;; increment: (rep: i32) -> new_rep: i32
    (func $increment (export "increment") (param i32) (result i32)
      (i32.add (local.get 0) (i32.const 1))
    )

    ;; add: (rep: i32, n: i32) -> new_rep: i32
    (func $add (export "add") (param i32 i32) (result i32)
      (i32.add (local.get 0) (local.get 1))
    )
  )

  (core instance $inst (instantiate $impl))

  ;; Resource type definition
  (type $counter (resource (rep i32)))

  ;; Function types
  (type $create-type (func (result (own $counter))))
  (type $get-type (func (param "c" (borrow $counter)) (result s32)))
  (type $increment-type (func (param "c" (own $counter)) (result (own $counter))))
  (type $add-type (func (param "c" (own $counter)) (param "n" s32) (result (own $counter))))

  ;; Alias core functions
  (alias core export $inst "create" (core func $core-create))
  (alias core export $inst "get" (core func $core-get))
  (alias core export $inst "increment" (core func $core-increment))
  (alias core export $inst "add" (core func $core-add))

  ;; Lift core functions to component functions
  (func $create (type $create-type)
    (canon lift (core func $core-create)))
  (func $get (type $get-type)
    (canon lift (core func $core-get)))
  (func $increment (type $increment-type)
    (canon lift (core func $core-increment)))
  (func $add (type $add-type)
    (canon lift (core func $core-add)))

  ;; Export the functions
  (export "create" (func $create))
  (export "get" (func $get))
  (export "increment" (func $increment))
  (export "add" (func $add))
)
