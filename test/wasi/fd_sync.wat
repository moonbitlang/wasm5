;; Test fd_sync - sync file to storage
;; Writes data, syncs, checks that sync returns success
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_sync"
    (func $fd_sync (param i32) (result i32)))

  (memory (export "memory") 1)

  ;; "Hello" at offset 0 (5 bytes)
  (data (i32.const 0) "Hello")
  ;; "ok" at offset 100
  (data (i32.const 100) "ok")

  (func (export "_start")
    (local $err i32)

    ;; Write iovec at 20: ptr=0, len=5
    (i32.store (i32.const 20) (i32.const 0))
    (i32.store (i32.const 24) (i32.const 5))

    ;; fd_write(fd=3, iovs=20, iovs_len=1, nwritten=32)
    (drop (call $fd_write (i32.const 3) (i32.const 20) (i32.const 1) (i32.const 32)))

    ;; fd_sync(fd=3)
    (local.set $err (call $fd_sync (i32.const 3)))

    ;; If sync succeeded, write "ok"
    (if (i32.eqz (local.get $err))
      (then
        ;; Write "ok" to the file to indicate success
        (i32.store (i32.const 50) (i32.const 100))  ;; ptr to "ok"
        (i32.store (i32.const 54) (i32.const 2))    ;; len = 2
        (drop (call $fd_write (i32.const 3) (i32.const 50) (i32.const 1) (i32.const 60)))
      )
    )
  )
)
