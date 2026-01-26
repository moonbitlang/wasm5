;; Test clock_time_get - writes "ok" if timestamp > 0
(module
  (import "wasi_snapshot_preview1" "clock_time_get"
    (func $clock_time_get (param i32 i64 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; "ok" at offset 200
  (data (i32.const 200) "ok")

  (func (export "_start")
    ;; clock_time_get(CLOCK_REALTIME=0, precision=0, timestamp_ptr=0)
    (drop (call $clock_time_get (i32.const 0) (i64.const 0) (i32.const 0)))

    ;; Check if timestamp > 0 (read 64-bit value at offset 0)
    (if (i64.gt_u (i64.load (i32.const 0)) (i64.const 0))
      (then
        ;; iovec at 108: ptr=200, len=2
        (i32.store (i32.const 108) (i32.const 200))
        (i32.store (i32.const 112) (i32.const 2))

        ;; Write "ok" to fd 3
        (drop (call $fd_write (i32.const 3) (i32.const 108) (i32.const 1) (i32.const 120)))
      )
    )
  )
)
