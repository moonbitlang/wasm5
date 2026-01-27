;; Test path_symlink + path_readlink using preopened dir (fd 4)
(module
  (import "wasi_snapshot_preview1" "path_symlink"
    (func $path_symlink (param i32 i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "path_readlink"
    (func $path_readlink (param i32 i32 i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  (data (i32.const 0) "target.txt")
  (data (i32.const 32) "sym.txt")
  (data (i32.const 210) "no")

  (func (export "_start")
    (local $err i32)
    (local $used i32)

    ;; path_symlink(old="target.txt", new="sym.txt")
    (local.set $err (call $path_symlink
      (i32.const 0)
      (i32.const 10)
      (i32.const 4)
      (i32.const 32)
      (i32.const 7)
    ))

    (if (i32.ne (local.get $err) (i32.const 0))
      (then
        (i32.store (i32.const 108) (i32.const 210))
        (i32.store (i32.const 112) (i32.const 2))
        (drop (call $fd_write (i32.const 3) (i32.const 108) (i32.const 1) (i32.const 120)))
        (return)
      )
    )

    ;; path_readlink(dirfd=4, path="sym.txt", buf=100, buf_len=64, bufused=180)
    (local.set $err (call $path_readlink
      (i32.const 4)
      (i32.const 32)
      (i32.const 7)
      (i32.const 100)
      (i32.const 64)
      (i32.const 180)
    ))

    (if (i32.ne (local.get $err) (i32.const 0))
      (then
        (i32.store (i32.const 108) (i32.const 210))
        (i32.store (i32.const 112) (i32.const 2))
        (drop (call $fd_write (i32.const 3) (i32.const 108) (i32.const 1) (i32.const 120)))
        (return)
      )
    )

    (local.set $used (i32.load (i32.const 180)))

    ;; write symlink target to fd 3 (use iovec outside buffer)
    (i32.store (i32.const 240) (i32.const 100))
    (i32.store (i32.const 244) (local.get $used))
    (drop (call $fd_write (i32.const 3) (i32.const 240) (i32.const 1) (i32.const 248)))
  )
)
