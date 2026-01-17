(module
    (memory 1 1)

    (func (export "run") (param $N i64) (result i64)
        (local $primes_count i32)
        (local $x i32)
        (local $n i32)
        ;; n = N as i32
        (local.set $n (i32.wrap_i64 (local.get $N)))
        ;; mem[0] = 2
        (i32.store (i32.const 0) (i32.const 2))
        ;; primes_count = 1
        (local.set $primes_count (i32.const 1))
        ;; x = 2
        (local.set $x (i32.const 2))
        (block $exit
            (loop $continue
                ;; x += 1
                (local.set $x
                    (i32.add (local.get $x) (i32.const 1))
                )
                ;; if primes_count >= n: break
                (br_if $exit
                    (i32.ge_s (local.get $primes_count) (local.get $n))
                )
                ;; if not is_prime(x): continue
                (br_if $continue
                    (i32.eqz (call $is_prime (local.get $x)))
                )
                ;; mem[primes_count * 4] = x
                (i32.store
                    (i32.mul (local.get $primes_count) (i32.const 4))
                    (local.get $x)
                )
                ;; primes_count += 1
                (local.set $primes_count
                    (i32.add (local.get $primes_count) (i32.const 1))
                )
                ;; continue
                (br $continue)
            )
        )
        ;; mem[(primes_count - 1) * 4] as i64
        (i64.extend_i32_u
            (i32.load
                (i32.mul
                    (i32.sub (local.get $primes_count) (i32.const 1))
                    (i32.const 4)
                )
            )
        )
    )

    (func $is_prime (param $x i32) (result i32)
        (local $prime i32)
        (local $i i32)
        ;; i = 0
        (local.set $i (i32.const 0))
        (loop $continue
            ;; prime = mem[i * 4]
            (local.set $prime
                (i32.load (i32.mul (local.get $i) (i32.const 4)))
            )
            ;; if prime * prime > x: return 1 (true)
            (if
                (i32.gt_s
                    (i32.mul (local.get $prime) (local.get $prime))
                    (local.get $x)
                )
                (then (return (i32.const 1)))
            )
            (if
                (i32.eq
                    (i32.rem_s (local.get $x) (local.get $prime))
                    (i32.const 0)
                )
                (then (return (i32.const 0)))
            )
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $continue)
        )
        (unreachable)
    )
)
