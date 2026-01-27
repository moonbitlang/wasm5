;; Test random_get - fills buffer and checks if not all zeros
(module
  (import "wasi_snapshot_preview1" "random_get"
    (func $random_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; "ok" at offset 200
  (data (i32.const 200) "ok")

  (func (export "_start")
    (local $i i32)
    (local $sum i32)

    ;; random_get(buf=0, len=16) - fill 16 bytes at offset 0
    (drop (call $random_get (i32.const 0) (i32.const 16)))

    ;; Sum all bytes to check if any are non-zero
    (local.set $i (i32.const 0))
    (local.set $sum (i32.const 0))
    (block $break
      (loop $loop
        (local.set $sum
          (i32.add (local.get $sum) (i32.load8_u (local.get $i))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br_if $break (i32.ge_u (local.get $i) (i32.const 16)))
        (br $loop)
      )
    )

    ;; If sum > 0, write "ok" (very unlikely all 16 bytes are zero)
    (if (i32.gt_u (local.get $sum) (i32.const 0))
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
