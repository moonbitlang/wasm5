;; Test fd_seek returns INVAL for invalid whence
(module
  (import "wasi_snapshot_preview1" "fd_seek"
    (func $fd_seek (param i32 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  (func (export "_start")
    (local $err i32)
    (local $len i32)

    ;; fd_seek(fd=3, offset=0, whence=3 (invalid), newoffset_ptr=40)
    (local.set $err (call $fd_seek (i32.const 3) (i64.const 0) (i32.const 3) (i32.const 40)))

    ;; Convert errno to ASCII at 100
    (if (i32.ge_u (local.get $err) (i32.const 10))
      (then
        (i32.store8 (i32.const 100)
          (i32.add (i32.const 48) (i32.div_u (local.get $err) (i32.const 10))))
        (i32.store8 (i32.const 101)
          (i32.add (i32.const 48) (i32.rem_u (local.get $err) (i32.const 10))))
        (local.set $len (i32.const 2))
      )
      (else
        (i32.store8 (i32.const 100)
          (i32.add (i32.const 48) (local.get $err)))
        (local.set $len (i32.const 1))
      )
    )

    ;; iovec at 108: ptr=100, len=$len
    (i32.store (i32.const 108) (i32.const 100))
    (i32.store (i32.const 112) (local.get $len))

    ;; Write errno string to fd 3
    (drop (call $fd_write (i32.const 3) (i32.const 108) (i32.const 1) (i32.const 120)))
  )
)
