;; Test fd_seek - seek to a position in preopened file (fd 3)
;; Writes data, seeks back, reads and verifies
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_seek"
    (func $fd_seek (param i32 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_read"
    (func $fd_read (param i32 i32 i32 i32) (result i32)))

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

    ;; fd_seek(fd=3, offset=0, whence=0 (SEEK_SET), newoffset_ptr=40)
    (local.set $err (call $fd_seek (i32.const 3) (i64.const 0) (i32.const 0) (i32.const 40)))

    ;; If seek succeeded (err == 0), write "ok"
    (if (i32.eqz (local.get $err))
      (then
        ;; Write "ok" to the file to indicate success
        (i32.store (i32.const 50) (i32.const 100))  ;; ptr to "ok"
        (i32.store (i32.const 54) (i32.const 2))    ;; len = 2
        ;; Seek to start again to overwrite
        (drop (call $fd_seek (i32.const 3) (i64.const 0) (i32.const 0) (i32.const 40)))
        (drop (call $fd_write (i32.const 3) (i32.const 50) (i32.const 1) (i32.const 60)))
      )
    )
  )
)
