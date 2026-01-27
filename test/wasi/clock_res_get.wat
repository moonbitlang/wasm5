;; Test clock_res_get - get clock resolution
;; Writes "ok" if clock resolution is successfully retrieved and > 0
(module
  (import "wasi_snapshot_preview1" "clock_res_get"
    (func $clock_res_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; "ok" at offset 200
  (data (i32.const 200) "ok")

  (func (export "_start")
    (local $err i32)

    ;; clock_res_get(clock_id=0 (CLOCK_REALTIME), resolution_ptr=0)
    (local.set $err (call $clock_res_get (i32.const 0) (i32.const 0)))

    ;; If succeeded and resolution > 0, write "ok"
    (if (i32.and
          (i32.eqz (local.get $err))
          (i64.gt_u (i64.load (i32.const 0)) (i64.const 0)))
      (then
        ;; iovec at 100: ptr=200, len=2
        (i32.store (i32.const 100) (i32.const 200))
        (i32.store (i32.const 104) (i32.const 2))
        (drop (call $fd_write (i32.const 3) (i32.const 100) (i32.const 1) (i32.const 110)))
      )
    )
  )
)
