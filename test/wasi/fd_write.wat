;; Test fd_write to preopened file (fd 3)
;; Writes "Hello, WASI!" to the preopened file
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; "Hello, WASI!" at offset 0 (12 bytes)
  (data (i32.const 0) "Hello, WASI!")

  ;; iovec at offset 20: ptr=0, len=12
  (data (i32.const 20) "\00\00\00\00\0c\00\00\00")

  (func (export "_start")
    ;; fd_write(fd=3, iovs=20, iovs_len=1, nwritten=32)
    ;; fd 3 is the preopened test file
    (drop (call $fd_write (i32.const 3) (i32.const 20) (i32.const 1) (i32.const 32)))
  )
)
