(component
  ;; Core module that echoes a string back (returns same ptr/len)
  (core module $impl
    (memory (export "memory") 1)
    (global $heap_ptr (mut i32) (i32.const 1024))

    (func $realloc (export "realloc") (param i32 i32 i32 i32) (result i32)
      (local $ptr i32)
      (local.set $ptr
        (i32.and
          (i32.add (global.get $heap_ptr) (i32.sub (local.get 2) (i32.const 1)))
          (i32.sub (i32.const 0) (local.get 2))))
      (global.set $heap_ptr (i32.add (local.get $ptr) (local.get 3)))
      (local.get $ptr)
    )

    ;; echo(ptr, len) -> (ptr, len) - returns the same string
    (func $echo (export "echo") (param i32 i32) (result i32 i32)
      local.get 0
      local.get 1
    )
  )

  (core instance $inst (instantiate $impl))

  (type $echo-type (func (param "s" string) (result string)))

  (alias core export $inst "echo" (core func $core-echo))
  (alias core export $inst "memory" (core memory $mem))
  (alias core export $inst "realloc" (core func $core-realloc))

  (func $echo (type $echo-type)
    (canon lift (core func $core-echo)
      (memory $mem)
      (realloc (func $core-realloc))))

  (export "echo" (func $echo))
)
