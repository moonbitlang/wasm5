;; Test fd_prestat_dir_name for preopened dir (fd 4)
(module
  (import "wasi_snapshot_preview1" "fd_prestat_get"
    (func $fd_prestat_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_prestat_dir_name"
    (func $fd_prestat_dir_name (param i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  (data (i32.const 210) "no")

  (func (export "_start")
    (local $err i32)
    (local $len i32)

    ;; fd_prestat_get(fd=4, buf=0)
    (local.set $err (call $fd_prestat_get (i32.const 4) (i32.const 0)))
    (if (i32.ne (local.get $err) (i32.const 0))
      (then
        (i32.store (i32.const 108) (i32.const 210))
        (i32.store (i32.const 112) (i32.const 2))
        (drop (call $fd_write (i32.const 3) (i32.const 108) (i32.const 1) (i32.const 120)))
        (return)
      )
    )

    ;; name_len from buf+4
    (local.set $len (i32.load (i32.const 4)))

    ;; fd_prestat_dir_name(fd=4, path_offset=16, path_len=32)
    (local.set $err (call $fd_prestat_dir_name (i32.const 4) (i32.const 16) (i32.const 32)))
    (if (i32.ne (local.get $err) (i32.const 0))
      (then
        (i32.store (i32.const 108) (i32.const 210))
        (i32.store (i32.const 112) (i32.const 2))
        (drop (call $fd_write (i32.const 3) (i32.const 108) (i32.const 1) (i32.const 120)))
        (return)
      )
    )

    ;; Write name to fd 3
    (i32.store (i32.const 108) (i32.const 16))
    (i32.store (i32.const 112) (local.get $len))
    (drop (call $fd_write (i32.const 3) (i32.const 108) (i32.const 1) (i32.const 120)))
  )
)
