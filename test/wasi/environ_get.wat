;; Test environ_get returns success and sizes are zero
(module
  (import "wasi_snapshot_preview1" "environ_sizes_get"
    (func $environ_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "environ_get"
    (func $environ_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  (data (i32.const 200) "ok")
  (data (i32.const 210) "no")

  (func (export "_start")
    (local $ok i32)

    (local.set $ok (i32.const 1))

    ;; environ_sizes_get(count=0, buf_size=4)
    (if (i32.ne (call $environ_sizes_get (i32.const 0) (i32.const 4)) (i32.const 0))
      (then (local.set $ok (i32.const 0)))
    )

    ;; environ_get(environ=8, environ_buf=16)
    (if (i32.ne (call $environ_get (i32.const 8) (i32.const 16)) (i32.const 0))
      (then (local.set $ok (i32.const 0)))
    )

    ;; count and size should be zero
    (if (i32.ne (i32.load (i32.const 0)) (i32.const 0))
      (then (local.set $ok (i32.const 0)))
    )
    (if (i32.ne (i32.load (i32.const 4)) (i32.const 0))
      (then (local.set $ok (i32.const 0)))
    )

    ;; Write ok/no to fd 3
    (if (local.get $ok)
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
