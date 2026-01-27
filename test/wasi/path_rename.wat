;; Test path_rename using preopened dir (fd 4)
(module
  (import "wasi_snapshot_preview1" "path_open"
    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_close"
    (func $fd_close (param i32) (result i32)))
  (import "wasi_snapshot_preview1" "path_rename"
    (func $path_rename (param i32 i32 i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  (data (i32.const 0) "old.txt")
  (data (i32.const 16) "new.txt")
  (data (i32.const 200) "ok")
  (data (i32.const 210) "no")

  (func (export "_start")
    (local $err i32)
    (local $fd i32)

    ;; Create old.txt via path_open
    (local.set $err (call $path_open
      (i32.const 4)
      (i32.const 0)
      (i32.const 0)
      (i32.const 7)
      (i32.const 9)
      (i64.const 70)
      (i64.const 0)
      (i32.const 0)
      (i32.const 100)
    ))
    (if (i32.eqz (local.get $err))
      (then
        (local.set $fd (i32.load (i32.const 100)))
        (drop (call $fd_close (local.get $fd)))
      )
    )

    ;; path_rename(old="old.txt", new="new.txt")
    (local.set $err (call $path_rename
      (i32.const 4)
      (i32.const 0)
      (i32.const 7)
      (i32.const 4)
      (i32.const 16)
      (i32.const 7)
    ))

    (if (i32.eqz (local.get $err))
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
