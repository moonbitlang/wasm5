;; Test environ_sizes_get - writes env count as ASCII digit to fd 3
(module
  (import "wasi_snapshot_preview1" "environ_sizes_get"
    (func $environ_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  (func (export "_start")
    ;; Get environ_count at offset 0, environ_buf_size at offset 4
    (drop (call $environ_sizes_get (i32.const 0) (i32.const 4)))

    ;; Convert environ_count to ASCII digit and store at offset 100
    (i32.store8 (i32.const 100)
      (i32.add (i32.const 48) (i32.load (i32.const 0))))

    ;; iovec at 108: ptr=100, len=1
    (i32.store (i32.const 108) (i32.const 100))
    (i32.store (i32.const 112) (i32.const 1))

    ;; Write to fd 3
    (drop (call $fd_write (i32.const 3) (i32.const 108) (i32.const 1) (i32.const 120)))
  )
)
