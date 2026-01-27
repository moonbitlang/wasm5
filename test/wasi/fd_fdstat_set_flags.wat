;; Test fd_fdstat_set_flags on preopened file (fd 3)
(module
  (import "wasi_snapshot_preview1" "fd_fdstat_set_flags"
    (func $fd_fdstat_set_flags (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  (data (i32.const 200) "ok")
  (data (i32.const 210) "no")

  (func (export "_start")
    (local $err i32)

    ;; flags = 0
    (local.set $err (call $fd_fdstat_set_flags (i32.const 3) (i32.const 0)))

    (if (i32.eqz (local.get $err))
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
