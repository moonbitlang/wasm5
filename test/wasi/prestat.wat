;; Test fd_prestat_get - checks that fd 3 is a valid preopen
(module
  (import "wasi_snapshot_preview1" "fd_prestat_get"
    (func $fd_prestat_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; "ok" at offset 200
  (data (i32.const 200) "ok")
  ;; "no" at offset 210
  (data (i32.const 210) "no")

  (func (export "_start")
    (local $result i32)

    ;; fd_prestat_get(fd=3, buf=0) - get prestat info for fd 3
    (local.set $result (call $fd_prestat_get (i32.const 3) (i32.const 0)))

    ;; If result == 0 (success), write "ok"
    (if (i32.eqz (local.get $result))
      (then
        ;; iovec at 108: ptr=200, len=2
        (i32.store (i32.const 108) (i32.const 200))
        (i32.store (i32.const 112) (i32.const 2))
        (drop (call $fd_write (i32.const 3) (i32.const 108) (i32.const 1) (i32.const 120)))
      )
      (else
        ;; iovec at 108: ptr=210, len=2
        (i32.store (i32.const 108) (i32.const 210))
        (i32.store (i32.const 112) (i32.const 2))
        (drop (call $fd_write (i32.const 3) (i32.const 108) (i32.const 1) (i32.const 120)))
      )
    )
  )
)
