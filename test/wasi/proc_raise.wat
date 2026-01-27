;; Test proc_raise returns NOSYS (52)
(module
  (import "wasi_snapshot_preview1" "proc_raise"
    (func $proc_raise (param i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  (data (i32.const 200) "52")
  (data (i32.const 210) "no")

  (func (export "_start")
    (local $err i32)

    (local.set $err (call $proc_raise (i32.const 0)))

    (if (i32.eq (local.get $err) (i32.const 52))
      (then
        (i32.store (i32.const 108) (i32.const 200))
        (i32.store (i32.const 112) (i32.const 2))
      )
      (else
        (i32.store (i32.const 108) (i32.const 210))
        (i32.store (i32.const 112) (i32.const 2))
      )
    )

    (drop (call $fd_write (i32.const 3) (i32.const 108) (i32.const 1) (i32.const 120)))
  )
)
