///|
fn op_f32_eq(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::I32(if a == b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f32_ne(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::I32(if a != b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f32_lt(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::I32(if a < b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f32_gt(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::I32(if a > b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f32_le(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::I32(if a <= b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f32_ge(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::I32(if a >= b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f64_eq(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::I32(if a == b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f64_ne(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::I32(if a != b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f64_lt(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::I32(if a < b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f64_gt(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::I32(if a > b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f64_le(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::I32(if a <= b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

///|
fn op_f64_ge(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::I32(if a >= b { 1U } else { 0U }))
  rt.pc += 1
  OK
}

// Float unary operations

///|
fn op_f32_neg(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(-a))
  rt.pc += 1
  OK
}

///|
fn op_f32_abs(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(a.abs()))
  rt.pc += 1
  OK
}

///|
fn op_f32_sqrt(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a.sqrt())))
  rt.pc += 1
  OK
}

///|
fn op_f32_ceil(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a.ceil())))
  rt.pc += 1
  OK
}

///|
fn op_f32_floor(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a.floor())))
  rt.pc += 1
  OK
}

///|
fn op_f32_trunc(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a.trunc())))
  rt.pc += 1
  OK
}

///|
fn op_f32_nearest(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(canonicalize_f32(rintf(a))))
  rt.pc += 1
  OK
}

///|
fn op_f64_neg(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(-a))
  rt.pc += 1
  OK
}

// Float binary operations

///|
fn op_f32_add(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a + b)))
  rt.pc += 1
  OK
}

///|
fn op_f32_sub(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a - b)))
  rt.pc += 1
  OK
}

///|
fn op_f32_mul(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a * b)))
  rt.pc += 1
  OK
}

///|
fn op_f32_div(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a / b)))
  rt.pc += 1
  OK
}

///|
fn op_f32_min(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
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
  rt.stack.push(Value::F32(result))
  rt.pc += 1
  OK
}

///|
fn op_f32_max(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
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
  rt.stack.push(Value::F32(result))
  rt.pc += 1
  OK
}

///|
fn op_f32_copysign(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f32()
  let a_bits = a.reinterpret_as_uint()
  let b_bits = b.reinterpret_as_uint()
  let sign_mask = 0x8000_0000U
  let result_bits = (a_bits & sign_mask.lnot()) | (b_bits & sign_mask)
  rt.stack.push(Value::F32(Float::reinterpret_from_uint(result_bits)))
  rt.pc += 1
  OK
}

///|
fn op_f64_add(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a + b)))
  rt.pc += 1
  OK
}

///|
fn op_f64_sub(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a - b)))
  rt.pc += 1
  OK
}

///|
fn op_f64_mul(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a * b)))
  rt.pc += 1
  OK
}

///|
fn op_f64_div(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a / b)))
  rt.pc += 1
  OK
}

///|
fn op_f64_min(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
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
  rt.stack.push(Value::F64(result))
  rt.pc += 1
  OK
}

///|
fn op_f64_max(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
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
  rt.stack.push(Value::F64(result))
  rt.pc += 1
  OK
}

///|
fn op_f64_copysign(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_f64()
  let a_bits = a.reinterpret_as_uint64()
  let b_bits = b.reinterpret_as_uint64()
  let sign_mask = 0x8000_0000_0000_0000UL
  let result_bits = (a_bits & sign_mask.lnot()) | (b_bits & sign_mask)
  rt.stack.push(Value::F64(result_bits.reinterpret_as_double()))
  rt.pc += 1
  OK
}

// Float unary operations

///|
fn op_f64_abs(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(a.abs()))
  rt.pc += 1
  OK
}

///|
fn op_f64_sqrt(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a.sqrt())))
  rt.pc += 1
  OK
}

///|
fn op_f64_ceil(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a.ceil())))
  rt.pc += 1
  OK
}

///|
fn op_f64_floor(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a.floor())))
  rt.pc += 1
  OK
}

///|
fn op_f64_trunc(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a.trunc())))
  rt.pc += 1
  OK
}

///|
fn op_f64_nearest(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(canonicalize_f64(rint(a))))
  rt.pc += 1
  OK
}

// Float conversion operations

///|
fn op_f64_convert_i64_u(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  rt.stack.push(Value::F64(a.to_double()))
  rt.pc += 1
  OK
}

///|
fn op_f64_convert_i64_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i64().reinterpret_as_int64()
  rt.stack.push(Value::F64(a.to_double()))
  rt.pc += 1
  OK
}

///|
fn op_f64_convert_i32_u(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  rt.stack.push(Value::F64(a.to_double()))
  rt.pc += 1
  OK
}

///|
fn op_f64_convert_i32_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i32().reinterpret_as_int()
  rt.stack.push(Value::F64(a.to_double()))
  rt.pc += 1
  OK
}

///|
fn op_f64_promote_f32(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  let result = a.to_double()
  // Canonicalize NaN to ensure positive canonical NaN
  rt.stack.push(Value::F64(canonicalize_f64(result)))
  rt.pc += 1
  OK
}

///|
fn op_f32_demote_f64(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  let result = Float::from_double(a)
  // Canonicalize NaN to ensure positive canonical NaN
  rt.stack.push(Value::F32(canonicalize_f32(result)))
  rt.pc += 1
  OK
}

///|
fn op_f32_convert_i32_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i32().reinterpret_as_int()
  rt.stack.push(Value::F32(Float::from_int(a)))
  rt.pc += 1
  OK
}

///|
fn op_f32_convert_i32_u(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  rt.stack.push(Value::F32(Float::from_double(a.to_double())))
  rt.pc += 1
  OK
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
fn op_f32_convert_i64_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i64().reinterpret_as_int64()
  rt.stack.push(Value::F32(f32_from_i64(a)))
  rt.pc += 1
  OK
}

///|
fn op_f32_convert_i64_u(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  rt.stack.push(Value::F32(f32_from_u64(a)))
  rt.pc += 1
  OK
}

// Truncation operations (with trapping on overflow/NaN)

///|
fn op_i64_trunc_f64_s(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  // Trap on NaN or out of range
  if a.is_nan() {
    return IntegerOverflow
  }
  if a >= 9223372036854775808.0 || a < -9223372036854775808.0 {
    return IntegerOverflow
  }
  rt.stack.push(Value::I64(a.to_int64().reinterpret_as_uint64()))
  rt.pc += 1
  OK
}

///|
fn op_i64_trunc_f64_u(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  // Trap on NaN or out of range
  if a.is_nan() {
    return IntegerOverflow
  }
  if a >= 18446744073709551616.0 || a <= -1.0 {
    return IntegerOverflow
  }
  // Use C function for proper conversion at precision boundaries
  rt.stack.push(Value::I64(u64_from_f64(a)))
  rt.pc += 1
  OK
}

///|
fn op_i32_trunc_f32_s(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  // Trap on NaN or out of range
  if a.is_nan() {
    return IntegerOverflow // "invalid conversion to integer"
  }
  if a >= 2147483648.0 || a < -2147483648.0 {
    return IntegerOverflow
  }
  rt.stack.push(Value::I32(a.to_int().reinterpret_as_uint()))
  rt.pc += 1
  OK
}

///|
fn op_i32_trunc_f32_u(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  // Trap on NaN or out of range
  if a.is_nan() {
    return IntegerOverflow
  }
  if a >= 4294967296.0 || a <= -1.0 {
    return IntegerOverflow
  }
  rt.stack.push(Value::I32(a.to_double().to_uint64().to_uint()))
  rt.pc += 1
  OK
}

///|
fn op_i32_trunc_f64_s(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  // Trap on NaN or out of range
  if a.is_nan() {
    return IntegerOverflow
  }
  if a >= 2147483648.0 || a <= -2147483649.0 {
    return IntegerOverflow
  }
  rt.stack.push(Value::I32(a.to_int().reinterpret_as_uint()))
  rt.pc += 1
  OK
}

///|
fn op_i32_trunc_f64_u(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  // Trap on NaN or out of range
  if a.is_nan() {
    return IntegerOverflow
  }
  if a >= 4294967296.0 || a <= -1.0 {
    return IntegerOverflow
  }
  rt.stack.push(Value::I32(a.to_uint64().to_uint()))
  rt.pc += 1
  OK
}

///|
fn op_i64_trunc_f32_s(rt : Runtime) -> RetCode {
  let a = rt.pop_f32().to_double()
  // Trap on NaN or out of range
  if a.is_nan() {
    return IntegerOverflow
  }
  if a >= 9223372036854775808.0 || a < -9223372036854775808.0 {
    return IntegerOverflow
  }
  rt.stack.push(Value::I64(a.to_int64().reinterpret_as_uint64()))
  rt.pc += 1
  OK
}

///|
fn op_i64_trunc_f32_u(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  // Trap on NaN or out of range
  if a.is_nan() {
    return IntegerOverflow
  }
  let a_double = a.to_double()
  if a_double >= 18446744073709551616.0 || a_double <= -1.0 {
    return IntegerOverflow
  }
  // Use C function for proper conversion at precision boundaries
  rt.stack.push(Value::I64(u64_from_f32(a)))
  rt.pc += 1
  OK
}

// =============================================================================
// Saturating Truncation Operations
// =============================================================================
// These operations convert floats to integers but instead of trapping on
// overflow/NaN, they "saturate" to the min/max value or return 0 for NaN.

///|
fn op_i32_trunc_sat_f32_s(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  let result = if a.is_nan() {
    0U
  } else if a >= 2147483648.0 {
    // >= 2^31, saturate to max i32
    0x7FFFFFFFU
  } else if a < -2147483648.0 {
    // < -2^31, saturate to min i32
    0x80000000U
  } else {
    a.to_int().reinterpret_as_uint()
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i32_trunc_sat_f32_u(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  let result = if a.is_nan() {
    0U
  } else if a >= 4294967296.0 {
    // >= 2^32, saturate to max u32
    0xFFFFFFFFU
  } else if a <= -1.0 {
    // negative, saturate to 0
    0U
  } else {
    a.to_double().to_uint64().to_uint()
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i32_trunc_sat_f64_s(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  let result = if a.is_nan() {
    0U
  } else if a >= 2147483648.0 {
    // >= 2^31, saturate to max i32
    0x7FFFFFFFU
  } else if a < -2147483648.0 {
    // < -2^31, saturate to min i32
    0x80000000U
  } else {
    a.to_int().reinterpret_as_uint()
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i32_trunc_sat_f64_u(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  let result = if a.is_nan() {
    0U
  } else if a >= 4294967296.0 {
    // >= 2^32, saturate to max u32
    0xFFFFFFFFU
  } else if a <= -1.0 {
    // negative, saturate to 0
    0U
  } else {
    a.to_uint64().to_uint()
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_trunc_sat_f32_s(rt : Runtime) -> RetCode {
  let a = rt.pop_f32().to_double()
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
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_trunc_sat_f32_u(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
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
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_trunc_sat_f64_s(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
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
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  OK
}

///|
fn op_i64_trunc_sat_f64_u(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
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
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  OK
}

// Reinterpret operations

///|
fn op_i32_reinterpret_f32(rt : Runtime) -> RetCode {
  let a = rt.pop_f32()
  rt.stack.push(Value::I32(a.reinterpret_as_uint()))
  rt.pc += 1
  OK
}

///|
fn op_i64_reinterpret_f64(rt : Runtime) -> RetCode {
  let a = rt.pop_f64()
  rt.stack.push(Value::I64(a.reinterpret_as_uint64()))
  rt.pc += 1
  OK
}

///|
fn op_f32_reinterpret_i32(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  rt.stack.push(Value::F32(Float::reinterpret_from_uint(a)))
  rt.pc += 1
  OK
}

///|
fn op_f64_reinterpret_i64(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  rt.stack.push(Value::F64(a.reinterpret_as_double()))
  rt.pc += 1
  OK
}

// Global operations
