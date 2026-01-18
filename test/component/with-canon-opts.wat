(component
  ;; Core module with string function
  (core module $m
    (memory (export "memory") 1)

    ;; Simple realloc function for string allocation
    (global $heap_ptr (mut i32) (i32.const 0))
    (func $realloc (export "realloc") (param $old_ptr i32) (param $old_size i32) (param $align i32) (param $new_size i32) (result i32)
      (local $ptr i32)
      (local.set $ptr (global.get $heap_ptr))
      (global.set $heap_ptr (i32.add (global.get $heap_ptr) (local.get $new_size)))
      (local.get $ptr)
    )

    ;; Function that takes a string (ptr, len) and returns length
    (func $string_len (export "string-len") (param $ptr i32) (param $len i32) (result i32)
      (local.get $len)
    )
  )

  ;; Instantiate the core module
  (core instance $i (instantiate $m))

  ;; Alias memory and realloc
  (alias core export $i "memory" (core memory $mem))
  (alias core export $i "realloc" (core func $realloc))
  (alias core export $i "string-len" (core func $string_len))

  ;; Define the component function type
  (type $len-type (func (param "s" string) (result u32)))

  ;; Lift the core function to component function with options
  (func $len (type $len-type)
    (canon lift (core func $string_len)
      (memory $mem)
      (realloc $realloc)
    )
  )

  ;; Export the component function
  (export "string-len" (func $len))
)
