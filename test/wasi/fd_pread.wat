;; Test fd_pread - read at offset without changing file position
;; Writes content, then reads from offset 0 using pread
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_pread"
    (func $fd_pread (param i32 i32 i32 i64 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_seek"
    (func $fd_seek (param i32 i64 i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; "ok" at offset 200
  (data (i32.const 200) "ok")
  ;; "Hello" at offset 0
  (data (i32.const 0) "Hello")

  (func (export "_start")
    (local $err i32)
    (local $nread i32)

    ;; First write "Hello" to file
    (i32.store (i32.const 20) (i32.const 0))   ;; iovec ptr = 0
    (i32.store (i32.const 24) (i32.const 5))   ;; iovec len = 5
    (drop (call $fd_write (i32.const 3) (i32.const 20) (i32.const 1) (i32.const 32)))

    ;; Now use pread to read 5 bytes from offset 0 into buffer at 50
    (i32.store (i32.const 40) (i32.const 50))  ;; iovec ptr = 50
    (i32.store (i32.const 44) (i32.const 5))   ;; iovec len = 5
    (local.set $err (call $fd_pread (i32.const 3) (i32.const 40) (i32.const 1) (i64.const 0) (i32.const 60)))

    ;; Get number of bytes read
    (local.set $nread (i32.load (i32.const 60)))

    ;; If succeeded and read 5 bytes and first char is 'H' (0x48)
    (if (i32.and
          (i32.eqz (local.get $err))
          (i32.and
            (i32.eq (local.get $nread) (i32.const 5))
            (i32.eq (i32.load8_u (i32.const 50)) (i32.const 0x48))))
      (then
        ;; Seek to beginning of file before writing "ok"
        (drop (call $fd_seek (i32.const 3) (i64.const 0) (i32.const 0) (i32.const 80)))
        ;; Write "ok" to signal success
        (i32.store (i32.const 100) (i32.const 200))
        (i32.store (i32.const 104) (i32.const 2))
        (drop (call $fd_write (i32.const 3) (i32.const 100) (i32.const 1) (i32.const 110)))
      )
    )
  )
)
