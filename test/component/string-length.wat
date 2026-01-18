(component
  ;; Core module with memory and string processing
  (core module $impl
    ;; Memory for string data
    (memory (export "memory") 1)

    ;; Simple bump allocator
    (global $heap_ptr (mut i32) (i32.const 1024))

    ;; realloc(old_ptr, old_size, align, new_size) -> ptr
    ;; Simple implementation that just bumps the heap pointer
    (func $realloc (export "realloc") (param i32 i32 i32 i32) (result i32)
      (local $ptr i32)
      ;; Align the current heap pointer
      (local.set $ptr
        (i32.and
          (i32.add (global.get $heap_ptr) (i32.sub (local.get 2) (i32.const 1)))
          (i32.sub (i32.const 0) (local.get 2))))
      ;; Update heap pointer
      (global.set $heap_ptr (i32.add (local.get $ptr) (local.get 3)))
      ;; Return the allocated pointer
      (local.get $ptr)
    )

    ;; string_length(ptr, len) -> len
    ;; Simply returns the length of the string (which is already passed as parameter)
    (func $string_length (export "string_length") (param i32 i32) (result i32)
      local.get 1
    )
  )

  ;; Instantiate the core module
  (core instance $inst (instantiate $impl))

  ;; Define component type for string function
  (type $string-length-type (func (param "s" string) (result u32)))

  ;; Alias core exports
  (alias core export $inst "string_length" (core func $core-string-length))
  (alias core export $inst "memory" (core memory $mem))
  (alias core export $inst "realloc" (core func $core-realloc))

  ;; Lift to component function with memory and realloc options
  (func $string-length (type $string-length-type)
    (canon lift (core func $core-string-length)
      (memory $mem)
      (realloc (func $core-realloc))))

  ;; Export the function
  (export "string-length" (func $string-length))
)
