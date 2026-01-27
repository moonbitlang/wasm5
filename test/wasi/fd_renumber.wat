;; Test fd_renumber on dynamically opened file
(module
  (import "wasi_snapshot_preview1" "path_open"
    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_renumber"
    (func $fd_renumber (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_close"
    (func $fd_close (param i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  (data (i32.const 0) "renum.txt")
  (data (i32.const 200) "ok")
  (data (i32.const 210) "no")

  (func (export "_start")
    (local $err i32)
    (local $fd i32)
    (local $err_old i32)
    (local $err_new i32)
    (local $ok i32)

    ;; path_open(dirfd=4, path="renum.txt")
    (local.set $err (call $path_open
      (i32.const 4)
      (i32.const 0)
      (i32.const 0)
      (i32.const 9)
      (i32.const 9)
      (i64.const 70)
      (i64.const 0)
      (i32.const 0)
      (i32.const 100)
    ))

    (if (i32.ne (local.get $err) (i32.const 0))
      (then
        (i32.store (i32.const 108) (i32.const 210))
        (i32.store (i32.const 112) (i32.const 2))
        (drop (call $fd_write (i32.const 3) (i32.const 108) (i32.const 1) (i32.const 120)))
        (return)
      )
    )

    (local.set $fd (i32.load (i32.const 100)))
    (local.set $err (call $fd_renumber (local.get $fd) (i32.const 9)))

    (if (i32.ne (local.get $err) (i32.const 0))
      (then
        (i32.store (i32.const 108) (i32.const 210))
        (i32.store (i32.const 112) (i32.const 2))
        (drop (call $fd_write (i32.const 3) (i32.const 108) (i32.const 1) (i32.const 120)))
        (return)
      )
    )

    (local.set $err_old (call $fd_close (local.get $fd)))
    (local.set $err_new (call $fd_close (i32.const 9)))

    (local.set $ok
      (i32.and
        (i32.eq (local.get $err_old) (i32.const 8))
        (i32.eq (local.get $err_new) (i32.const 0))
      )
    )

    (if (local.get $ok)
      (then
        (i32.store (i32.const 108) (i32.const 200))
        (i32.store (i32.const 112) (i32.const 2))
      )
      (else
        (i32.store (i32.const 108) (i32.const 210))
        (i32.store (i32.const 112) (i32.const 2))
      )
    )

    (drop (call $fd_write (i32.const 3) (i32.const 108) (i32.const 1) (i32.const 120)))
  )
)
