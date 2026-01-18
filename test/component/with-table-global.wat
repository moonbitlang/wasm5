(component
  ;; Core module with table and global
  (core module $m
    (table (export "table") 1 funcref)
    (global (export "counter") (mut i32) (i32.const 0))
    (memory (export "memory") 1)

    (func $get_counter (export "get-counter") (result i32)
      global.get 0
    )

    (func $inc_counter (export "inc-counter")
      global.get 0
      i32.const 1
      i32.add
      global.set 0
    )
  )

  ;; Instantiate
  (core instance $i (instantiate $m))

  ;; Alias table, global, memory, and functions
  (alias core export $i "table" (core table $tbl))
  (alias core export $i "counter" (core global $cnt))
  (alias core export $i "memory" (core memory $mem))
  (alias core export $i "get-counter" (core func $get))
  (alias core export $i "inc-counter" (core func $inc))

  ;; Types
  (type $get-type (func (result u32)))
  (type $inc-type (func))

  ;; Lift functions
  (func $get_counter (type $get-type)
    (canon lift (core func $get))
  )
  (func $inc_counter (type $inc-type)
    (canon lift (core func $inc))
  )

  ;; Export
  (export "get-counter" (func $get_counter))
  (export "inc-counter" (func $inc_counter))
)
