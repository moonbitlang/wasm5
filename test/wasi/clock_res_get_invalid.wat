;; Test clock_res_get returns INVAL for unsupported clock_id
(module
  (import "wasi_snapshot_preview1" "clock_res_get"
    (func $clock_res_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  (func (export "_start")
    (local $err i32)
    (local $len i32)

    ;; clock_res_get(clock_id=2 (invalid), res_ptr=0)
    (local.set $err (call $clock_res_get (i32.const 2) (i32.const 0)))

    ;; Convert errno to ASCII at 100
    (if (i32.ge_u (local.get $err) (i32.const 10))
      (then
        (i32.store8 (i32.const 100)
          (i32.add (i32.const 48) (i32.div_u (local.get $err) (i32.const 10))))
        (i32.store8 (i32.const 101)
          (i32.add (i32.const 48) (i32.rem_u (local.get $err) (i32.const 10))))
        (local.set $len (i32.const 2))
      )
      (else
        (i32.store8 (i32.const 100)
          (i32.add (i32.const 48) (local.get $err)))
        (local.set $len (i32.const 1))
      )
    )

    ;; iovec at 108: ptr=100, len=$len
    (i32.store (i32.const 108) (i32.const 100))
    (i32.store (i32.const 112) (local.get $len))

    ;; Write errno string to fd 3
    (drop (call $fd_write (i32.const 3) (i32.const 108) (i32.const 1) (i32.const 120)))
  )
)
