;; Test fd_pwrite - write at offset without changing file position
;; Writes "Hello", then uses pwrite to overwrite beginning with "ok"
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_pwrite"
    (func $fd_pwrite (param i32 i32 i32 i64 i32) (result i32)))

  (memory (export "memory") 1)

  ;; "ok" at offset 200
  (data (i32.const 200) "ok")
  ;; "Hello" at offset 0
  (data (i32.const 0) "Hello")

  (func (export "_start")
    (local $err i32)

    ;; First write "Hello" to file
    (i32.store (i32.const 20) (i32.const 0))   ;; iovec ptr = 0
    (i32.store (i32.const 24) (i32.const 5))   ;; iovec len = 5
    (drop (call $fd_write (i32.const 3) (i32.const 20) (i32.const 1) (i32.const 32)))

    ;; Use pwrite to write "ok" at offset 0
    ;; This should result in "okllo" (overwriting first 2 chars of "Hello")
    (i32.store (i32.const 40) (i32.const 200)) ;; iovec ptr = 200 ("ok")
    (i32.store (i32.const 44) (i32.const 2))   ;; iovec len = 2
    (local.set $err (call $fd_pwrite (i32.const 3) (i32.const 40) (i32.const 1) (i64.const 0) (i32.const 60)))

    ;; pwrite should succeed - file now contains "okllo"
    ;; The test harness will verify the file content
  )
)
