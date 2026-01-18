(module
    (func $fib (export "run") (param $N i64) (result i64)
        (if
            (i64.le_s (local.get $N) (i64.const 1))
            (then (return (local.get $N)))
        )
        (i64.add
            (call $fib
                (i64.sub (local.get $N) (i64.const 1))
            )
            (call $fib
                (i64.sub (local.get $N) (i64.const 2))
            )
        )
    )
)
