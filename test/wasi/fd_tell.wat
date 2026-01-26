;; Test fd_tell - get current file position
;; Writes data then checks position matches bytes written
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_tell"
    (func $fd_tell (param i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; "Hello" at offset 0 (5 bytes)
  (data (i32.const 0) "Hello")
  ;; "ok" at offset 100
  (data (i32.const 100) "ok")

  (func (export "_start")
    (local $err i32)
    (local $pos i64)

    ;; Write iovec at 20: ptr=0, len=5
    (i32.store (i32.const 20) (i32.const 0))
    (i32.store (i32.const 24) (i32.const 5))

    ;; fd_write(fd=3, iovs=20, iovs_len=1, nwritten=32)
    (drop (call $fd_write (i32.const 3) (i32.const 20) (i32.const 1) (i32.const 32)))

    ;; fd_tell(fd=3, offset_ptr=40)
    (local.set $err (call $fd_tell (i32.const 3) (i32.const 40)))

    ;; Get the position from offset 40
    (local.set $pos (i64.load (i32.const 40)))

    ;; If tell succeeded and position is 5, write "ok"
    (if (i32.and
          (i32.eqz (local.get $err))
          (i64.eq (local.get $pos) (i64.const 5)))
      (then
        ;; Write "ok" to the file to indicate success
        (i32.store (i32.const 50) (i32.const 100))  ;; ptr to "ok"
        (i32.store (i32.const 54) (i32.const 2))    ;; len = 2
        (drop (call $fd_write (i32.const 3) (i32.const 50) (i32.const 1) (i32.const 60)))
      )
    )
  )
)
