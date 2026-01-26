;; Test fd_read from preopened file (fd 3)
;; Reads content and writes to fd 3 (same file, seeking is not needed for test)
(module
  (import "wasi_snapshot_preview1" "fd_read"
    (func $fd_read (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  (func (export "_start")
    ;; Read iovec at 20: ptr=0, len=100 (read up to 100 bytes into offset 0)
    (i32.store (i32.const 20) (i32.const 0))
    (i32.store (i32.const 24) (i32.const 100))

    ;; fd_read(fd=3, iovs=20, iovs_len=1, nread=32)
    (drop (call $fd_read (i32.const 3) (i32.const 20) (i32.const 1) (i32.const 32)))

    ;; Get nread from offset 32
    ;; Write iovec at 40: ptr=0, len=nread
    (i32.store (i32.const 40) (i32.const 0))
    (i32.store (i32.const 44) (i32.load (i32.const 32)))

    ;; Write read content back to stdout (fd=1) so we can verify
    (drop (call $fd_write (i32.const 1) (i32.const 40) (i32.const 1) (i32.const 52)))
  )
)
