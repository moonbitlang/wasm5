// ============================================================================
// i32 instruction implementations
// ============================================================================

///|
fn op_i32_const(rt : Runtime) -> Unit {
  let value = rt.read_imm_i32()
  rt.stack.unsafe_set(rt.stack_top, value.to_uint64())
  rt.stack_top += 1
  rt.pc += 1
  ()
}

///|
fn op_i32_add(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(rt.stack_top - 1, (a + b).to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i32_sub(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(rt.stack_top - 1, (a - b).to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i32_mul(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(rt.stack_top - 1, (a * b).to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i32_div_s(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  if b == 0U {
    rt.error_detail = "division by zero"
    rt.status = Trap
    return
  }
  if a == 0x80000000U && b == 0xFFFFFFFFU {
    rt.error_detail = "integer overflow"
    rt.status = Trap
    return
  }
  let result = (a.reinterpret_as_int() / b.reinterpret_as_int()).reinterpret_as_uint()
  rt.stack.unsafe_set(rt.stack_top - 1, result.to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i32_div_u(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  if b == 0U {
    rt.error_detail = "division by zero"
    rt.status = Trap
    return
  }
  rt.stack.unsafe_set(rt.stack_top - 1, (a / b).to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i32_rem_s(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  if b == 0U {
    rt.error_detail = "division by zero"
    rt.status = Trap
    return
  }
  // INT_MIN % -1 = 0, but division would overflow and cause SIGFPE
  if a == 0x80000000U && b == 0xFFFFFFFFU {
    rt.stack.unsafe_set(rt.stack_top - 1, 0UL)
    rt.pc += 1
    return
  }
  let result = (a.reinterpret_as_int() % b.reinterpret_as_int()).reinterpret_as_uint()
  rt.stack.unsafe_set(rt.stack_top - 1, result.to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i32_rem_u(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  if b == 0U {
    rt.error_detail = "division by zero"
    rt.status = Trap
    return
  }
  rt.stack.unsafe_set(rt.stack_top - 1, (a % b).to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i32_and(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(rt.stack_top - 1, (a & b).to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i32_or(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(rt.stack_top - 1, (a | b).to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i32_xor(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(rt.stack_top - 1, (a ^ b).to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i32_shl(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  let shift = (b & 0x1FU).reinterpret_as_int()
  rt.stack.unsafe_set(rt.stack_top - 1, (a << shift).to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i32_shr_s(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  let shift = (b & 0x1FU).reinterpret_as_int()
  let result = (a.reinterpret_as_int() >> shift).reinterpret_as_uint()
  rt.stack.unsafe_set(rt.stack_top - 1, result.to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i32_shr_u(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  let shift = (b & 0x1FU).reinterpret_as_int()
  rt.stack.unsafe_set(rt.stack_top - 1, (a >> shift).to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i32_rotl(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  let rotation = (b & 0x1FU).reinterpret_as_int()
  let result = (a << rotation) | (a >> (32 - rotation))
  rt.stack.unsafe_set(rt.stack_top - 1, result.to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i32_rotr(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  let rotation = (b & 0x1FU).reinterpret_as_int()
  let result = (a >> rotation) | (a << (32 - rotation))
  rt.stack.unsafe_set(rt.stack_top - 1, result.to_uint64())
  rt.pc += 1
  ()
}

// Comparison operations

///|
fn op_i32_eq(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(rt.stack_top - 1, if a == b { 1UL } else { 0UL })
  rt.pc += 1
  ()
}

///|
fn op_i32_ne(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(rt.stack_top - 1, if a != b { 1UL } else { 0UL })
  rt.pc += 1
  ()
}

///|
fn op_i32_lt_s(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  let result = if a.reinterpret_as_int() < b.reinterpret_as_int() {
    1UL
  } else {
    0UL
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  ()
}

///|
fn op_i32_lt_u(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(rt.stack_top - 1, if a < b { 1UL } else { 0UL })
  rt.pc += 1
  ()
}

///|
fn op_i32_gt_s(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  let result = if a.reinterpret_as_int() > b.reinterpret_as_int() {
    1UL
  } else {
    0UL
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  ()
}

///|
fn op_i32_gt_u(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(rt.stack_top - 1, if a > b { 1UL } else { 0UL })
  rt.pc += 1
  ()
}

///|
fn op_i32_le_s(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  let result = if a.reinterpret_as_int() <= b.reinterpret_as_int() {
    1UL
  } else {
    0UL
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  ()
}

///|
fn op_i32_le_u(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(rt.stack_top - 1, if a <= b { 1UL } else { 0UL })
  rt.pc += 1
  ()
}

///|
fn op_i32_ge_s(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  let result = if a.reinterpret_as_int() >= b.reinterpret_as_int() {
    1UL
  } else {
    0UL
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  ()
}

///|
fn op_i32_ge_u(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top).to_uint()
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(rt.stack_top - 1, if a >= b { 1UL } else { 0UL })
  rt.pc += 1
  ()
}

// Unary operations

///|
fn op_i32_eqz(rt : Runtime) -> Unit {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(rt.stack_top - 1, if a == 0U { 1UL } else { 0UL })
  rt.pc += 1
  ()
}

///|
fn op_i32_clz(rt : Runtime) -> Unit {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    a.clz().reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  ()
}

///|
fn op_i32_ctz(rt : Runtime) -> Unit {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    a.ctz().reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  ()
}

///|
fn op_i32_popcnt(rt : Runtime) -> Unit {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(
    rt.stack_top - 1,
    a.popcnt().reinterpret_as_uint().to_uint64(),
  )
  rt.pc += 1
  ()
}

///|
fn op_i32_extend8_s(rt : Runtime) -> Unit {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  let byte = a & 0xFFU
  let result = if (byte & 0x80U) != 0U { byte | 0xFFFFFF00U } else { byte }
  rt.stack.unsafe_set(rt.stack_top - 1, result.to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i32_extend16_s(rt : Runtime) -> Unit {
  let a = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  let half = a & 0xFFFFU
  let result = if (half & 0x8000U) != 0U { half | 0xFFFF0000U } else { half }
  rt.stack.unsafe_set(rt.stack_top - 1, result.to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i32_wrap_i64(rt : Runtime) -> Unit {
  let v = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, v & 0xFFFFFFFFUL)
  rt.pc += 1
  ()
}

// ============================================================================
// i64 instruction implementations
// ============================================================================

///|
fn op_i64_const(rt : Runtime) -> Unit {
  // Read two i32 immediates to form i64
  let low = rt.read_imm_i32()
  let high = rt.read_imm_i32()
  let value = low.to_uint64() | (high.to_uint64() << 32)
  rt.stack.unsafe_set(rt.stack_top, value)
  rt.stack_top += 1
  rt.pc += 1
  ()
}

///|
fn op_f32_const(rt : Runtime) -> Unit {
  let bits = rt.read_imm_i32()
  rt.stack.unsafe_set(rt.stack_top, bits.to_uint64())
  rt.stack_top += 1
  rt.pc += 1
  ()
}

///|
fn op_f64_const(rt : Runtime) -> Unit {
  let low = rt.read_imm_i32()
  let high = rt.read_imm_i32()
  let bits = low.to_uint64() | (high.to_uint64() << 32)
  rt.stack.unsafe_set(rt.stack_top, bits)
  rt.stack_top += 1
  rt.pc += 1
  ()
}

///|
fn op_i64_add(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, a + b)
  rt.pc += 1
  ()
}

///|
fn op_i64_sub(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, a - b)
  rt.pc += 1
  ()
}

///|
fn op_i64_mul(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, a * b)
  rt.pc += 1
  ()
}

///|
fn op_i64_div_s(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  if b == 0UL {
    rt.error_detail = "division by zero"
    rt.status = Trap
    return
  }
  if a == 0x8000000000000000UL && b == 0xFFFFFFFFFFFFFFFFUL {
    rt.error_detail = "integer overflow"
    rt.status = Trap
    return
  }
  let result = (a.reinterpret_as_int64() / b.reinterpret_as_int64()).reinterpret_as_uint64()
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  ()
}

///|
fn op_i64_div_u(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  if b == 0UL {
    rt.error_detail = "division by zero"
    rt.status = Trap
    return
  }
  rt.stack.unsafe_set(rt.stack_top - 1, a / b)
  rt.pc += 1
  ()
}

///|
fn op_i64_rem_s(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  if b == 0UL {
    rt.error_detail = "division by zero"
    rt.status = Trap
    return
  }
  // INT64_MIN % -1 = 0, but division would overflow and cause SIGFPE
  if a == 0x8000000000000000UL && b == 0xFFFFFFFFFFFFFFFFUL {
    rt.stack.unsafe_set(rt.stack_top - 1, 0UL)
    rt.pc += 1
    return
  }
  let result = (a.reinterpret_as_int64() % b.reinterpret_as_int64()).reinterpret_as_uint64()
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  ()
}

///|
fn op_i64_rem_u(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  if b == 0UL {
    rt.error_detail = "division by zero"
    rt.status = Trap
    return
  }
  rt.stack.unsafe_set(rt.stack_top - 1, a % b)
  rt.pc += 1
  ()
}

///|
fn op_i64_and(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, a & b)
  rt.pc += 1
  ()
}

///|
fn op_i64_or(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, a | b)
  rt.pc += 1
  ()
}

///|
fn op_i64_xor(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, a ^ b)
  rt.pc += 1
  ()
}

///|
fn op_i64_shl(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  let shift = (b & 0x3FUL).to_int()
  rt.stack.unsafe_set(rt.stack_top - 1, a << shift)
  rt.pc += 1
  ()
}

///|
fn op_i64_shr_s(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  let shift = (b & 0x3FUL).to_int()
  let result = (a.reinterpret_as_int64() >> shift).reinterpret_as_uint64()
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  ()
}

///|
fn op_i64_shr_u(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  let shift = (b & 0x3FUL).to_int()
  rt.stack.unsafe_set(rt.stack_top - 1, a >> shift)
  rt.pc += 1
  ()
}

///|
fn op_i64_rotl(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  let rotation = (b & 0x3FUL).to_int()
  let result = (a << rotation) | (a >> (64 - rotation))
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  ()
}

///|
fn op_i64_rotr(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  let rotation = (b & 0x3FUL).to_int()
  let result = (a >> rotation) | (a << (64 - rotation))
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  ()
}

// Comparison operations

///|
fn op_i64_eq(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, if a == b { 1UL } else { 0UL })
  rt.pc += 1
  ()
}

///|
fn op_i64_ne(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, if a != b { 1UL } else { 0UL })
  rt.pc += 1
  ()
}

///|
fn op_i64_lt_s(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  let result = if a.reinterpret_as_int64() < b.reinterpret_as_int64() {
    1UL
  } else {
    0UL
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  ()
}

///|
fn op_i64_lt_u(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, if a < b { 1UL } else { 0UL })
  rt.pc += 1
  ()
}

///|
fn op_i64_gt_s(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  let result = if a.reinterpret_as_int64() > b.reinterpret_as_int64() {
    1UL
  } else {
    0UL
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  ()
}

///|
fn op_i64_gt_u(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, if a > b { 1UL } else { 0UL })
  rt.pc += 1
  ()
}

///|
fn op_i64_le_s(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  let result = if a.reinterpret_as_int64() <= b.reinterpret_as_int64() {
    1UL
  } else {
    0UL
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  ()
}

///|
fn op_i64_le_u(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, if a <= b { 1UL } else { 0UL })
  rt.pc += 1
  ()
}

///|
fn op_i64_ge_s(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  let result = if a.reinterpret_as_int64() >= b.reinterpret_as_int64() {
    1UL
  } else {
    0UL
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  ()
}

///|
fn op_i64_ge_u(rt : Runtime) -> Unit {
  rt.stack_top -= 1
  let b = rt.stack.unsafe_get(rt.stack_top)
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, if a >= b { 1UL } else { 0UL })
  rt.pc += 1
  ()
}

// Unary operations

///|
fn op_i64_eqz(rt : Runtime) -> Unit {
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, if a == 0UL { 1UL } else { 0UL })
  rt.pc += 1
  ()
}

///|
fn op_i64_clz(rt : Runtime) -> Unit {
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, a.clz().to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i64_ctz(rt : Runtime) -> Unit {
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, a.ctz().to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i64_popcnt(rt : Runtime) -> Unit {
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  rt.stack.unsafe_set(rt.stack_top - 1, a.popcnt().to_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i64_extend8_s(rt : Runtime) -> Unit {
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  let byte = a & 0xFFUL
  let result = if (byte & 0x80UL) != 0UL {
    byte | 0xFFFFFFFFFFFFFF00UL
  } else {
    byte
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  ()
}

///|
fn op_i64_extend16_s(rt : Runtime) -> Unit {
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  let half = a & 0xFFFFUL
  let result = if (half & 0x8000UL) != 0UL {
    half | 0xFFFFFFFFFFFF0000UL
  } else {
    half
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  ()
}

///|
fn op_i64_extend32_s(rt : Runtime) -> Unit {
  let a = rt.stack.unsafe_get(rt.stack_top - 1)
  let word = a & 0xFFFFFFFFUL
  let result = if (word & 0x80000000UL) != 0UL {
    word | 0xFFFFFFFF00000000UL
  } else {
    word
  }
  rt.stack.unsafe_set(rt.stack_top - 1, result)
  rt.pc += 1
  ()
}

// Extension operations

///|
fn op_i64_extend_i32_s(rt : Runtime) -> Unit {
  let v = rt.stack.unsafe_get(rt.stack_top - 1).to_uint().reinterpret_as_int()
  rt.stack.unsafe_set(rt.stack_top - 1, v.to_int64().reinterpret_as_uint64())
  rt.pc += 1
  ()
}

///|
fn op_i64_extend_i32_u(rt : Runtime) -> Unit {
  let v = rt.stack.unsafe_get(rt.stack_top - 1).to_uint()
  rt.stack.unsafe_set(rt.stack_top - 1, v.to_uint64())
  rt.pc += 1
  ()
}
