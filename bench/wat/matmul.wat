(module
    ;; 8 pages satisfy the memory requirement for roughly N <= 200.
    (memory 8 8)
    (global $size_of_f32 i32 (i32.const 4))
    ;; Matrix multiplication of 2 NxN matrices.
    ;; The function returns 0 to keep it aligned to other benchmark functions.
    ;;
    ;; This function uses the linear memory in the following way:
    ;;
    ;; - mem[0..N*N): `lhs` matrix
    ;; - mem[N*N..N*N*2): `rhs` matrix
    ;; - mem[N*N*2..N*N*3): `result` matrix
    ;;
    ;; - There need to be enough linear memory pages to provide
    ;;   at least N*N*3 elements to operate on to run this function
    ;; - Each element is a `f32` and occupies 4 bytes.
    ;; - There is no padding or alignment for the matrices to keep it simple.
    ;;
    ;; Implements the following pseudo-code:
    ;;
    ;; fn matmul(n: i64) -> i64 {
    ;;     offset_lhs = 0
    ;;     offset_rhs = n*n
    ;;     offset_res = rhs*2;
    ;;     for i in 0..n {
    ;;         for j in 0..n {
    ;;             mem[offset_res + (i * n) + j] = 0
    ;;             for k in 0..n {
    ;;                 mem[offset_res + (i * n) + j] += mem[offset_lhs + (i * n) + k] * mem[offset_rhs + (k * n) + j]
    ;;             }
    ;;         }
    ;;     }
    ;; }
    (func (export "run") (param $N i64) (result i64)
        (local $offset_lhs i32) ;; offset in bytes to `lhs` matrix
        (local $offset_rhs i32) ;; offset in bytes to `rhs` matrix
        (local $offset_res i32) ;; offset in bytes to result matrix
        (local $n i32)
        (local $i i32)
        (local $j i32)
        (local $k i32)
        (local $tmp i32)
        ;; n = N as i32
        (local.set $n (i32.wrap_i64 (local.get $N)))
        ;; offset_lhs = 0
        (local.set $offset_lhs (i32.const 0))
        ;; offset_rhs = N * N
        (local.set $offset_rhs (i32.mul (local.get $n) (local.get $n)))
        ;; offset_res = offset_rhs * 2
        (local.set $offset_res (i32.mul (local.get $offset_rhs) (i32.const 2)))
        (block $break_i
            ;; i = 0
            (local.set $i (i32.const 0))
            (loop $continue_i
                ;; if i >= n: break
                (br_if $break_i (i32.ge_u (local.get $i) (local.get $n)))
                (block $break_j
                    ;; j = 0
                    (local.set $j (i32.const 0))
                    (loop $continue_j
                        ;; if j >= n: break
                        (br_if $break_j (i32.ge_u (local.get $j) (local.get $n)))
                        ;; tmp = offset_res + (i * n) + j
                        (local.set $tmp
                            (i32.mul
                                (i32.add
                                    (local.get $offset_res)
                                    (i32.add
                                        (i32.mul (local.get $i) (local.get $n))
                                        (local.get $j)
                                    )
                                )
                                (global.get $size_of_f32)
                            )
                        )
                        ;; mem[tmp] = 0
                        (f32.store (local.get $tmp) (f32.const 0.0))
                        (block $break_k
                            ;; k = 0
                            (local.set $k (i32.const 0))
                            (loop $continue_k
                                ;; if k >= n: break
                                (br_if $break_k (i32.ge_u (local.get $k) (local.get $n)))
                                ;; mem[tmp] += mem[offset_lhs + (i * n) + k] * mem[offset_rhs + (k * n) + j]
                                (f32.store
                                    (local.get $tmp)
                                    (f32.add
                                        (f32.load (local.get $tmp))
                                        (f32.mul
                                            (f32.load
                                                (i32.mul
                                                    ;; offset_lhs + (i * n) + k
                                                    (i32.add
                                                        (local.get $offset_lhs)
                                                        (i32.add
                                                            (i32.mul (local.get $i) (local.get $n))
                                                            (local.get $k)
                                                        )
                                                    )
                                                    (global.get $size_of_f32)
                                                )
                                            )
                                            (f32.load
                                                (i32.mul
                                                    ;; offset_rhs + (k * n) + j
                                                    (i32.add
                                                        (local.get $offset_rhs)
                                                        (i32.add
                                                            (i32.mul (local.get $k) (local.get $n))
                                                            (local.get $j)
                                                        )
                                                    )
                                                    (global.get $size_of_f32)
                                                )
                                            )
                                        )
                                    )
                                )
                                ;; k += 1
                                (local.set $k (i32.add (local.get $k) (i32.const 1)))
                                (br $continue_k)
                            )
                        )
                        ;; j += 1
                        (local.set $j (i32.add (local.get $j) (i32.const 1)))
                        (br $continue_j)
                    )
                )
                ;; i += 1
                (local.set $i (i32.add (local.get $i) (i32.const 1)))
                (br $continue_i)
            )
        )
        (i64.const 0)
    )
)
