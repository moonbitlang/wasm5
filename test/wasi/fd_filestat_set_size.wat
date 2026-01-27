;; Test fd_filestat_set_size - truncate file to specified size
;; Writes "Hello World", truncates to 5 bytes, verifies via fd_filestat_get
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_filestat_set_size"
    (func $fd_filestat_set_size (param i32 i64) (result i32)))
  (import "wasi_snapshot_preview1" "fd_filestat_get"
    (func $fd_filestat_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_seek"
    (func $fd_seek (param i32 i64 i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; "ok" at offset 200
  (data (i32.const 200) "ok")
  ;; "Hello World" at offset 0 (11 bytes)
  (data (i32.const 0) "Hello World")

  (func (export "_start")
    (local $err i32)

    ;; Write "Hello World" to file
    (i32.store (i32.const 20) (i32.const 0))   ;; iovec ptr = 0
    (i32.store (i32.const 24) (i32.const 11))  ;; iovec len = 11
    (drop (call $fd_write (i32.const 3) (i32.const 20) (i32.const 1) (i32.const 32)))

    ;; Truncate to 5 bytes
    (local.set $err (call $fd_filestat_set_size (i32.const 3) (i64.const 5)))

    ;; If truncate succeeded, verify size via fd_filestat_get
    (if (i32.eqz (local.get $err))
      (then
        ;; Get file stats into buffer at offset 64
        (drop (call $fd_filestat_get (i32.const 3) (i32.const 64)))

        ;; filestat structure: size is at offset 32 (u64)
        ;; So size is at 64 + 32 = 96
        (if (i64.eq (i64.load (i32.const 96)) (i64.const 5))
          (then
            ;; Seek to beginning of file before writing "ok"
            (drop (call $fd_seek (i32.const 3) (i64.const 0) (i32.const 0) (i32.const 120)))
            ;; Write "ok" to signal success
            (i32.store (i32.const 100) (i32.const 200))
            (i32.store (i32.const 104) (i32.const 2))
            (drop (call $fd_write (i32.const 3) (i32.const 100) (i32.const 1) (i32.const 110)))
          )
        )
      )
    )
  )
)
