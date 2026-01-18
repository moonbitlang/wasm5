(component
  ;; Core module that sums a list of i32
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

    ;; sum(ptr, len) -> i32
    ;; Sums all i32 values in the list
    (func $sum (export "sum") (param $ptr i32) (param $len i32) (result i32)
      (local $i i32)
      (local $total i32)
      (local.set $i (i32.const 0))
      (local.set $total (i32.const 0))
      (block $done
        (loop $loop
          (br_if $done (i32.ge_u (local.get $i) (local.get $len)))
          (local.set $total
            (i32.add
              (local.get $total)
              (i32.load
                (i32.add
                  (local.get $ptr)
                  (i32.mul (local.get $i) (i32.const 4))))))
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
          (br $loop)
        )
      )
      (local.get $total)
    )
  )

  (core instance $inst (instantiate $impl))

  ;; Define type for list<s32> -> s32
  (type $sum-type (func (param "values" (list s32)) (result s32)))

  (alias core export $inst "sum" (core func $core-sum))
  (alias core export $inst "memory" (core memory $mem))
  (alias core export $inst "realloc" (core func $core-realloc))

  (func $sum (type $sum-type)
    (canon lift (core func $core-sum)
      (memory $mem)
      (realloc (func $core-realloc))))

  (export "sum" (func $sum))
)
