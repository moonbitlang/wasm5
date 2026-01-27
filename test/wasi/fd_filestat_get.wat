;; Test fd_filestat_get - get file stats
;; Checks that the function returns success
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_filestat_get"
    (func $fd_filestat_get (param i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; "ok" at offset 200
  (data (i32.const 200) "ok")

  (func (export "_start")
    (local $err i32)

    ;; fd_filestat_get(fd=3, buf=0)
    ;; Buffer at 0 needs 64 bytes for filestat structure
    (local.set $err (call $fd_filestat_get (i32.const 3) (i32.const 0)))

    ;; If succeeded, write "ok"
    (if (i32.eqz (local.get $err))
      (then
        ;; Write "ok" to the file to indicate success
        (i32.store (i32.const 100) (i32.const 200))  ;; ptr to "ok"
        (i32.store (i32.const 104) (i32.const 2))    ;; len = 2
        (drop (call $fd_write (i32.const 3) (i32.const 100) (i32.const 1) (i32.const 110)))
      )
    )
  )
)
