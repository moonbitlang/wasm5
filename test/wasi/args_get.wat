;; Test args_get - write argv[0] ("wasm5") to fd 3
(module
  (import "wasi_snapshot_preview1" "args_sizes_get"
    (func $args_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "args_get"
    (func $args_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  (func (export "_start")
    (local $ptr i32)

    ;; args_sizes_get(argc=0, argv_buf_size=4)
    (drop (call $args_sizes_get (i32.const 0) (i32.const 4)))

    ;; args_get(argv=8, argv_buf=16)
    (drop (call $args_get (i32.const 8) (i32.const 16)))

    ;; argv[0] pointer
    (local.set $ptr (i32.load (i32.const 8)))

    ;; iovec at 108: ptr=argv[0], len=5
    (i32.store (i32.const 108) (local.get $ptr))
    (i32.store (i32.const 112) (i32.const 5))

    ;; Write argv[0] to fd 3
    (drop (call $fd_write (i32.const 3) (i32.const 108) (i32.const 1) (i32.const 120)))
  )
)
