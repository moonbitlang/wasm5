;; Test sched_yield - yield CPU
;; Calls sched_yield and verifies it returns success (0)
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "sched_yield"
    (func $sched_yield (result i32)))

  (memory (export "memory") 1)

  ;; "ok" at offset 100
  (data (i32.const 100) "ok")

  (func (export "_start")
    (local $err i32)

    ;; sched_yield()
    (local.set $err (call $sched_yield))

    ;; If yield succeeded, write "ok"
    (if (i32.eqz (local.get $err))
      (then
        ;; Write "ok" to the file to indicate success
        (i32.store (i32.const 20) (i32.const 100))  ;; ptr to "ok"
        (i32.store (i32.const 24) (i32.const 2))    ;; len = 2
        (drop (call $fd_write (i32.const 3) (i32.const 20) (i32.const 1) (i32.const 32)))
      )
    )
  )
)
