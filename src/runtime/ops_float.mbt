///|
fn op_f32_eq(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top).to_uint(),
  )
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  rt.stack.unsafe_set(rt.stack_top - 1, if a == b { 1UL } else { 0UL })
  rt.pc += 1
  rt
}

///|
fn op_f32_ne(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top).to_uint(),
  )
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  rt.stack.unsafe_set(rt.stack_top - 1, if a != b { 1UL } else { 0UL })
  rt.pc += 1
  rt
}

///|
fn op_f32_lt(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top).to_uint(),
  )
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  rt.stack.unsafe_set(rt.stack_top - 1, if a < b { 1UL } else { 0UL })
  rt.pc += 1
  rt
}

///|
fn op_f32_gt(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top).to_uint(),
  )
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  rt.stack.unsafe_set(rt.stack_top - 1, if a > b { 1UL } else { 0UL })
  rt.pc += 1
  rt
}

///|
fn op_f32_le(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top).to_uint(),
  )
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  rt.stack.unsafe_set(rt.stack_top - 1, if a <= b { 1UL } else { 0UL })
  rt.pc += 1
  rt
}

///|
fn op_f32_ge(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top).to_uint(),
  )
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  rt.stack.unsafe_set(rt.stack_top - 1, if a >= b { 1UL } else { 0UL })
  rt.pc += 1
  rt
}

///|
fn op_f64_eq(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).reinterpret_as_double()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  rt.stack.unsafe_set(rt.stack_top - 1, if a == b { 1UL } else { 0UL })
  rt.pc += 1
  rt
}

///|
fn op_f64_ne(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).reinterpret_as_double()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  rt.stack.unsafe_set(rt.stack_top - 1, if a != b { 1UL } else { 0UL })
  rt.pc += 1
  rt
}

///|
fn op_f64_lt(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).reinterpret_as_double()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  rt.stack.unsafe_set(rt.stack_top - 1, if a < b { 1UL } else { 0UL })
  rt.pc += 1
  rt
}

///|
fn op_f64_gt(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).reinterpret_as_double()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  rt.stack.unsafe_set(rt.stack_top - 1, if a > b { 1UL } else { 0UL })
  rt.pc += 1
  rt
}

///|
fn op_f64_le(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).reinterpret_as_double()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  rt.stack.unsafe_set(rt.stack_top - 1, if a <= b { 1UL } else { 0UL })
  rt.pc += 1
  rt
}

///|
fn op_f64_ge(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).reinterpret_as_double()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  rt.stack.unsafe_set(rt.stack_top - 1, if a >= b { 1UL } else { 0UL })
  rt.pc += 1
  rt
}

// Float unary operations

///|
fn op_f32_neg(rt : Runtime) -> Runtime {
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  rt.stack.unsafe_set(rt.stack_top - 1, (-a).reinterpret_as_uint().to_uint64())
  rt.pc += 1
  rt
}

///|
fn op_f32_abs(rt : Runtime) -> Runtime {
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    a.abs().reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f32_sqrt(rt : Runtime) -> Runtime {
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f32(a.sqrt()).reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f32_ceil(rt : Runtime) -> Runtime {
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f32(a.ceil()).reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f32_floor(rt : Runtime) -> Runtime {
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f32(a.floor()).reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f32_trunc(rt : Runtime) -> Runtime {
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f32(a.trunc()).reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f32_nearest(rt : Runtime) -> Runtime {
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f32(rintf(a)).reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f64_neg(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  rt.stack.unsafe_set(rt.stack_top - 1, (-a).reinterpret_as_uint64())
  rt.pc += 1
  rt
}

// Float binary operations

///|
fn op_f32_add(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top).to_uint(),
  )
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f32(a + b).reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f32_sub(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top).to_uint(),
  )
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f32(a - b).reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f32_mul(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top).to_uint(),
  )
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f32(a * b).reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f32_div(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top).to_uint(),
  )
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f32(a / b).reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f32_min(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top).to_uint(),
  )
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  let result = if a.is_nan() || b.is_nan() {
    canonical_nan_f32
  } else if a < b {
    a
  } else if b < a {
    b
  } else {
    // a == b, but we need to handle signed zeros
    // -0.0 is considered "smaller" than +0.0 for min
    // Check sign bits: if either is negative zero, return negative zero
    let a_bits = a.reinterpret_as_uint()
    let b_bits = b.reinterpret_as_uint()
    let sign_mask = 0x8000_0000U
    if (a_bits & sign_mask) != 0U || (b_bits & sign_mask) != 0U {
      // At least one is negative, return the one with negative sign
      if (a_bits & sign_mask) != 0U {
        a
      } else {
        b
      }
    } else {
      a // Both positive, return either
    }
  }
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    result.reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f32_max(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top).to_uint(),
  )
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  let result = if a.is_nan() || b.is_nan() {
    canonical_nan_f32
  } else if a > b {
    a
  } else if b > a {
    b
  } else {
    // a == b, but we need to handle signed zeros
    // +0.0 is considered "larger" than -0.0 for max
    // Check sign bits: if either is positive zero, return positive zero
    let a_bits = a.reinterpret_as_uint()
    let b_bits = b.reinterpret_as_uint()
    let sign_mask = 0x8000_0000U
    if (a_bits & sign_mask) == 0U || (b_bits & sign_mask) == 0U {
      // At least one is positive, return the one with positive sign
      if (a_bits & sign_mask) == 0U {
        a
      } else {
        b
      }
    } else {
      a // Both negative, return either
    }
  }
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    result.reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f32_copysign(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top).to_uint(),
  )
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  let a_bits = a.reinterpret_as_uint()
  let b_bits = b.reinterpret_as_uint()
  let sign_mask = 0x8000_0000U
  let result_bits = (a_bits & sign_mask.lnot()) | (b_bits & sign_mask)
  rt.stack.unsafe_set(rt.stack_top - 1, result_bits.to_uint64())
  rt.pc += 1
  rt
}

///|
fn op_f64_add(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).reinterpret_as_double()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f64(a + b).reinterpret_as_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f64_sub(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).reinterpret_as_double()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f64(a - b).reinterpret_as_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f64_mul(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).reinterpret_as_double()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f64(a * b).reinterpret_as_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f64_div(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).reinterpret_as_double()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f64(a / b).reinterpret_as_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f64_min(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).reinterpret_as_double()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  // WebAssembly min semantics: if either is NaN, return canonical NaN
  let result = if a.is_nan() || b.is_nan() {
    canonical_nan_f64
  } else if a < b {
    a
  } else if b < a {
    b
  } else {
    // a == b, but we need to handle signed zeros
    // -0.0 is considered "smaller" than +0.0 for min
    let a_bits = a.reinterpret_as_uint64()
    let b_bits = b.reinterpret_as_uint64()
    let sign_mask = 0x8000_0000_0000_0000UL
    if (a_bits & sign_mask) != 0UL || (b_bits & sign_mask) != 0UL {
      // At least one is negative, return the one with negative sign
      if (a_bits & sign_mask) != 0UL {
        a
      } else {
        b
      }
    } else {
      a // Both positive, return either
    }
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result.reinterpret_as_uint64())
  rt.pc += 1
  rt
}

///|
fn op_f64_max(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).reinterpret_as_double()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  // WebAssembly max semantics: if either is NaN, return canonical NaN
  let result = if a.is_nan() || b.is_nan() {
    canonical_nan_f64
  } else if a > b {
    a
  } else if b > a {
    b
  } else {
    // a == b, but we need to handle signed zeros
    // +0.0 is considered "larger" than -0.0 for max
    let a_bits = a.reinterpret_as_uint64()
    let b_bits = b.reinterpret_as_uint64()
    let sign_mask = 0x8000_0000_0000_0000UL
    if (a_bits & sign_mask) == 0UL || (b_bits & sign_mask) == 0UL {
      // At least one is positive, return the one with positive sign
      if (a_bits & sign_mask) == 0UL {
        a
      } else {
        b
      }
    } else {
      a // Both negative, return either
    }
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result.reinterpret_as_uint64())
  rt.pc += 1
  rt
}

///|
fn op_f64_copysign(rt : Runtime) -> Runtime {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).reinterpret_as_double()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  let a_bits = a.reinterpret_as_uint64()
  let b_bits = b.reinterpret_as_uint64()
  let sign_mask = 0x8000_0000_0000_0000UL
  let result_bits = (a_bits & sign_mask.lnot()) | (b_bits & sign_mask)
  rt.stack.unsafe_set(rt.stack_top - 1, result_bits)
  rt.pc += 1
  rt
}

// Float unary operations

///|
fn op_f64_abs(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  rt.stack.unsafe_set(rt.stack_top - 1, a.abs().reinterpret_as_uint64())
  rt.pc += 1
  rt
}

///|
fn op_f64_sqrt(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f64(a.sqrt()).reinterpret_as_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f64_ceil(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f64(a.ceil()).reinterpret_as_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f64_floor(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f64(a.floor()).reinterpret_as_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f64_trunc(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f64(a.trunc()).reinterpret_as_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f64_nearest(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f64(rint(a)).reinterpret_as_uint64(),
  )
  rt.pc += 1
  rt
}

// Float conversion operations

///|
fn op_f64_convert_i64_u(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, a.to_double().reinterpret_as_uint64())
  rt.pc += 1
  rt
}

///|
fn op_f64_convert_i64_s(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_int64()
  rt.stack.unsafe_set(rt.stack_top - 1, a.to_double().reinterpret_as_uint64())
  rt.pc += 1
  rt
}

///|
fn op_f64_convert_i32_u(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(rt.stack_top - 1, a.to_double().reinterpret_as_uint64())
  rt.pc += 1
  rt
}

///|
fn op_f64_convert_i32_s(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint().reinterpret_as_int()
  rt.stack.unsafe_set(rt.stack_top - 1, a.to_double().reinterpret_as_uint64())
  rt.pc += 1
  rt
}

///|
fn op_f64_promote_f32(rt : Runtime) -> Runtime {
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  let result = a.to_double()
  // Canonicalize NaN to ensure positive canonical NaN
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f64(result).reinterpret_as_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f32_demote_f64(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  let result = Float::from_double(a)
  // Canonicalize NaN to ensure positive canonical NaN
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    canonicalize_f32(result).reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f32_convert_i32_s(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint().reinterpret_as_int()
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    Float::from_int(a).reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f32_convert_i32_u(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    Float::from_double(a.to_double()).reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

///|
extern "C" fn f32_from_i64(a : Int64) -> Float = "f32_from_i64"

///|
extern "C" fn f32_from_u64(a : UInt64) -> Float = "f32_from_u64"

///|
extern "C" fn u64_from_f32(a : Float) -> UInt64 = "u64_from_f32"

///|
extern "C" fn u64_from_f64(a : Double) -> UInt64 = "u64_from_f64"

///|
fn op_f32_convert_i64_s(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_int64()
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    f32_from_i64(a).reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_f32_convert_i64_u(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    f32_from_u64(a).reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

// Truncation operations (with trapping on overflow/NaN)

///|
fn op_i64_trunc_f64_s(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  // Trap on NaN or out of range
  if a.is_nan() {
    rt.error_detail = "integer overflow"
    rt.status = Trap
    return rt
  }
  if a >= 9223372036854775808.0 || a < -9223372036854775808.0 {
    rt.error_detail = "integer overflow"
    rt.status = Trap
    return rt
  }
  rt.stack.unsafe_set(rt.stack_top - 1, a.to_int64().reinterpret_as_uint64())
  rt.pc += 1
  rt
}

///|
fn op_i64_trunc_f64_u(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  // Trap on NaN or out of range
  if a.is_nan() {
    rt.error_detail = "integer overflow"
    rt.status = Trap
    return rt
  }
  if a >= 18446744073709551616.0 || a <= -1.0 {
    rt.error_detail = "integer overflow"
    rt.status = Trap
    return rt
  }
  // Use C function for proper conversion at precision boundaries
  rt.stack.unsafe_set(rt.stack_top - 1, u64_from_f64(a))
  rt.pc += 1
  rt
}

///|
fn op_i32_trunc_f32_s(rt : Runtime) -> Runtime {
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  // Trap on NaN or out of range
  if a.is_nan() {
    rt.error_detail = "integer overflow"
    rt.status = Trap
    return rt
  }
  if a >= 2147483648.0 || a < -2147483648.0 {
    rt.error_detail = "integer overflow"
    rt.status = Trap
    return rt
  }
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    a.to_int().reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_i32_trunc_f32_u(rt : Runtime) -> Runtime {
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  // Trap on NaN or out of range
  if a.is_nan() {
    rt.error_detail = "integer overflow"
    rt.status = Trap
    return rt
  }
  if a >= 4294967296.0 || a <= -1.0 {
    rt.error_detail = "integer overflow"
    rt.status = Trap
    return rt
  }
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    a.to_double().to_uint64() & 0xFFFFFFFFUL,
  )
  rt.pc += 1
  rt
}

///|
fn op_i32_trunc_f64_s(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  // Trap on NaN or out of range
  if a.is_nan() {
    rt.error_detail = "integer overflow"
    rt.status = Trap
    return rt
  }
  if a >= 2147483648.0 || a <= -2147483649.0 {
    rt.error_detail = "integer overflow"
    rt.status = Trap
    return rt
  }
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    a.to_int().reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  rt
}

///|
fn op_i32_trunc_f64_u(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  // Trap on NaN or out of range
  if a.is_nan() {
    rt.error_detail = "integer overflow"
    rt.status = Trap
    return rt
  }
  if a >= 4294967296.0 || a <= -1.0 {
    rt.error_detail = "integer overflow"
    rt.status = Trap
    return rt
  }
  rt.stack.unsafe_set(rt.stack_top - 1, a.to_uint64() & 0xFFFFFFFFUL)
  rt.pc += 1
  rt
}

///|
fn op_i64_trunc_f32_s(rt : Runtime) -> Runtime {
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  ).to_double()
  // Trap on NaN or out of range
  if a.is_nan() {
    rt.error_detail = "integer overflow"
    rt.status = Trap
    return rt
  }
  if a >= 9223372036854775808.0 || a < -9223372036854775808.0 {
    rt.error_detail = "integer overflow"
    rt.status = Trap
    return rt
  }
  rt.stack.unsafe_set(rt.stack_top - 1, a.to_int64().reinterpret_as_uint64())
  rt.pc += 1
  rt
}

///|
fn op_i64_trunc_f32_u(rt : Runtime) -> Runtime {
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  // Trap on NaN or out of range
  if a.is_nan() {
    rt.error_detail = "integer overflow"
    rt.status = Trap
    return rt
  }
  let a_double = a.to_double()
  if a_double >= 18446744073709551616.0 || a_double <= -1.0 {
    rt.error_detail = "integer overflow"
    rt.status = Trap
    return rt
  }
  // Use C function for proper conversion at precision boundaries
  rt.stack.unsafe_set(rt.stack_top - 1, u64_from_f32(a))
  rt.pc += 1
  rt
}

// =============================================================================
// Saturating Truncation Operations
// =============================================================================
// These operations convert floats to integers but instead of trapping on
// overflow/NaN, they "saturate" to the min/max value or return 0 for NaN.

///|
fn op_i32_trunc_sat_f32_s(rt : Runtime) -> Runtime {
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  let result = if a.is_nan() {
    0UL
  } else if a >= 2147483648.0 {
    // >= 2^31, saturate to max i32
    0x7FFFFFFFUL
  } else if a < -2147483648.0 {
    // < -2^31, saturate to min i32
    0x80000000UL
  } else {
    a.to_int().reinterpret_as_uint().to_uint64()
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  rt
}

///|
fn op_i32_trunc_sat_f32_u(rt : Runtime) -> Runtime {
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  let result = if a.is_nan() {
    0UL
  } else if a >= 4294967296.0 {
    // >= 2^32, saturate to max u32
    0xFFFFFFFFUL
  } else if a <= -1.0 {
    // negative, saturate to 0
    0UL
  } else {
    a.to_double().to_uint64() & 0xFFFFFFFFUL
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  rt
}

///|
fn op_i32_trunc_sat_f64_s(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  let result = if a.is_nan() {
    0UL
  } else if a >= 2147483648.0 {
    // >= 2^31, saturate to max i32
    0x7FFFFFFFUL
  } else if a < -2147483648.0 {
    // < -2^31, saturate to min i32
    0x80000000UL
  } else {
    a.to_int().reinterpret_as_uint().to_uint64()
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  rt
}

///|
fn op_i32_trunc_sat_f64_u(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  let result = if a.is_nan() {
    0UL
  } else if a >= 4294967296.0 {
    // >= 2^32, saturate to max u32
    0xFFFFFFFFUL
  } else if a <= -1.0 {
    // negative, saturate to 0
    0UL
  } else {
    a.to_uint64() & 0xFFFFFFFFUL
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  rt
}

///|
fn op_i64_trunc_sat_f32_s(rt : Runtime) -> Runtime {
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  ).to_double()
  let result = if a.is_nan() {
    0UL
  } else if a >= 9223372036854775808.0 {
    // >= 2^63, saturate to max i64
    0x7FFFFFFFFFFFFFFFUL
  } else if a < -9223372036854775808.0 {
    // < -2^63, saturate to min i64
    0x8000000000000000UL
  } else {
    a.to_int64().reinterpret_as_uint64()
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  rt
}

///|
fn op_i64_trunc_sat_f32_u(rt : Runtime) -> Runtime {
  let a = Float::reinterpret_from_uint(
    rt.stack.unsafe_get(rt.stack_top - 1).to_uint(),
  )
  let a_double = a.to_double()
  let result = if a.is_nan() {
    0UL
  } else if a_double >= 18446744073709551616.0 {
    // >= 2^64, saturate to max u64
    0xFFFFFFFFFFFFFFFFUL
  } else if a_double <= -1.0 {
    // negative, saturate to 0
    0UL
  } else {
    // Use C function for proper conversion at precision boundaries
    u64_from_f32(a)
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  rt
}

///|
fn op_i64_trunc_sat_f64_s(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  let result = if a.is_nan() {
    0UL
  } else if a >= 9223372036854775808.0 {
    // >= 2^63, saturate to max i64
    0x7FFFFFFFFFFFFFFFUL
  } else if a < -9223372036854775808.0 {
    // < -2^63, saturate to min i64
    0x8000000000000000UL
  } else {
    a.to_int64().reinterpret_as_uint64()
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  rt
}

///|
fn op_i64_trunc_sat_f64_u(rt : Runtime) -> Runtime {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).reinterpret_as_double()
  let result = if a.is_nan() {
    0UL
  } else if a >= 18446744073709551616.0 {
    // >= 2^64, saturate to max u64
    0xFFFFFFFFFFFFFFFFUL
  } else if a <= -1.0 {
    // negative, saturate to 0
    0UL
  } else {
    // Use C function for proper conversion at precision boundaries
    u64_from_f64(a)
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  rt
}

// Reinterpret operations

///|
fn op_i32_reinterpret_f32(rt : Runtime) -> Runtime {
  // Already stored as bits, just mask to i32 range
  let v = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, v & 0xFFFFFFFFUL)
  rt.pc += 1
  rt
}

///|
fn op_i64_reinterpret_f64(rt : Runtime) -> Runtime {
  // Already stored as bits, no change needed
  rt.pc += 1
  rt
}

///|
fn op_f32_reinterpret_i32(rt : Runtime) -> Runtime {
  // Already stored as bits, no change needed
  rt.pc += 1
  rt
}

///|
fn op_f64_reinterpret_i64(rt : Runtime) -> Runtime {
  // Already stored as bits, no change needed
  rt.pc += 1
  rt
}

// Global operations
