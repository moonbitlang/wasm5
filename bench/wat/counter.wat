(module
    (func (export "run") (param $n i64) (result i64)
        (local $i i64)
        ;; i = 0
        (local.set $i (i64.const 0))
        (block $break
            (loop $continue
                ;; if i >= n: break
                (br_if $break (i64.ge_u (local.get $i) (local.get $n)))
                ;; i += 1
                (local.set $i
                    (i64.add
                        (local.get $i)
                        (i64.const 1)
                    )
                )
                (br $continue)
            )
        )
        (local.get $n)
    )
)
