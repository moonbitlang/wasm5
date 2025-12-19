// ============================================================================
// i32 instruction implementations
// ============================================================================

///|
#tailcall
fn op_i32_const(rt : Runtime) -> RetCode {
  let value = rt.read_imm_i32()
  rt.stack.push(Value::I32(value))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_add(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(a + b))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_sub(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(a - b))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_mul(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(a * b))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_div_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  if b == 0U {
    rt.running = false
    return DivisionByZero
  }
  if a == 0x80000000U && b == 0xFFFFFFFFU {
    rt.running = false
    return IntegerOverflow
  }
  let result = (a.reinterpret_as_int() / b.reinterpret_as_int()).reinterpret_as_uint()
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_div_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  if b == 0U {
    rt.running = false
    return DivisionByZero
  }
  rt.stack.push(Value::I32(a / b))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_rem_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  if b == 0U {
    rt.running = false
    return DivisionByZero
  }
  let result = (a.reinterpret_as_int() % b.reinterpret_as_int()).reinterpret_as_uint()
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_rem_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  if b == 0U {
    rt.running = false
    return DivisionByZero
  }
  rt.stack.push(Value::I32(a % b))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_and(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(a & b))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_or(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(a | b))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_xor(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(a ^ b))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_shl(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  let shift = (b & 0x1FU).reinterpret_as_int()
  rt.stack.push(Value::I32(a << shift))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_shr_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  let shift = (b & 0x1FU).reinterpret_as_int()
  let result = (a.reinterpret_as_int() >> shift).reinterpret_as_uint()
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_shr_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  let shift = (b & 0x1FU).reinterpret_as_int()
  rt.stack.push(Value::I32(a >> shift))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_rotl(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  let rotation = (b & 0x1FU).reinterpret_as_int()
  let result = (a << rotation) | (a >> (32 - rotation))
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_rotr(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  let rotation = (b & 0x1FU).reinterpret_as_int()
  let result = (a >> rotation) | (a << (32 - rotation))
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  return next_op(rt)
}

// Comparison operations

///|
#tailcall
fn op_i32_eq(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(if a == b { 1U } else { 0U }))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_ne(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(if a != b { 1U } else { 0U }))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_lt_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  let result = if a.reinterpret_as_int() < b.reinterpret_as_int() {
    1U
  } else {
    0U
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_lt_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(if a < b { 1U } else { 0U }))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_gt_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  let result = if a.reinterpret_as_int() > b.reinterpret_as_int() {
    1U
  } else {
    0U
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_gt_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(if a > b { 1U } else { 0U }))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_le_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  let result = if a.reinterpret_as_int() <= b.reinterpret_as_int() {
    1U
  } else {
    0U
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_le_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(if a <= b { 1U } else { 0U }))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_ge_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  let result = if a.reinterpret_as_int() >= b.reinterpret_as_int() {
    1U
  } else {
    0U
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_ge_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(if a >= b { 1U } else { 0U }))
  rt.pc += 1
  return next_op(rt)
}

// Unary operations

///|
#tailcall
fn op_i32_eqz(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  rt.stack.push(Value::I32(if a == 0U { 1U } else { 0U }))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_clz(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  rt.stack.push(Value::I32(a.clz().reinterpret_as_uint()))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_ctz(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  rt.stack.push(Value::I32(a.ctz().reinterpret_as_uint()))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_popcnt(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  rt.stack.push(Value::I32(a.popcnt().reinterpret_as_uint()))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_extend8_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  let byte = a & 0xFFU
  let result = if (byte & 0x80U) != 0U { byte | 0xFFFFFF00U } else { byte }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_extend16_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  let half = a & 0xFFFFU
  let result = if (half & 0x8000U) != 0U { half | 0xFFFF0000U } else { half }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i32_wrap_i64(rt : Runtime) -> RetCode {
  match rt.stack.unsafe_pop() {
    Value::I64(v) => rt.stack.push(Value::I32((v & 0xFFFFFFFFUL).to_uint()))
    _ => abort("Type error: expected i64")
  }
  rt.pc += 1
  return next_op(rt)
}

// ============================================================================
// i64 instruction implementations
// ============================================================================

///|
#tailcall
fn op_i64_const(rt : Runtime) -> RetCode {
  // Read two i32 immediates to form i64
  let low = rt.read_imm_i32()
  let high = rt.read_imm_i32()
  let value = low.to_uint64() | (high.to_uint64() << 32)
  rt.stack.push(Value::I64(value))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_f32_const(rt : Runtime) -> RetCode {
  let bits = rt.read_imm_i32()
  rt.stack.push(Value::F32(Float::reinterpret_from_uint(bits)))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_f64_const(rt : Runtime) -> RetCode {
  let low = rt.read_imm_i32()
  let high = rt.read_imm_i32()
  let bits = low.to_uint64() | (high.to_uint64() << 32)
  rt.stack.push(Value::F64(bits.reinterpret_as_double()))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_add(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I64(a + b))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_sub(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I64(a - b))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_mul(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I64(a * b))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_div_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  if b == 0UL {
    rt.running = false
    return DivisionByZero
  }
  if a == 0x8000000000000000UL && b == 0xFFFFFFFFFFFFFFFFUL {
    rt.running = false
    return IntegerOverflow
  }
  let result = (a.reinterpret_as_int64() / b.reinterpret_as_int64()).reinterpret_as_uint64()
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_div_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  if b == 0UL {
    rt.running = false
    return DivisionByZero
  }
  rt.stack.push(Value::I64(a / b))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_rem_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  if b == 0UL {
    rt.running = false
    return DivisionByZero
  }
  let result = (a.reinterpret_as_int64() % b.reinterpret_as_int64()).reinterpret_as_uint64()
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_rem_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  if b == 0UL {
    rt.running = false
    return DivisionByZero
  }
  rt.stack.push(Value::I64(a % b))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_and(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I64(a & b))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_or(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I64(a | b))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_xor(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I64(a ^ b))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_shl(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  let shift = (b & 0x3FUL).to_int()
  rt.stack.push(Value::I64(a << shift))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_shr_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  let shift = (b & 0x3FUL).to_int()
  let result = (a.reinterpret_as_int64() >> shift).reinterpret_as_uint64()
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_shr_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  let shift = (b & 0x3FUL).to_int()
  rt.stack.push(Value::I64(a >> shift))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_rotl(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  let rotation = (b & 0x3FUL).to_int()
  let result = (a << rotation) | (a >> (64 - rotation))
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_rotr(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  let rotation = (b & 0x3FUL).to_int()
  let result = (a >> rotation) | (a << (64 - rotation))
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  return next_op(rt)
}

// i64 comparison operations

///|
#tailcall
fn op_i64_eq(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I32(if a == b { 1U } else { 0U }))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_ne(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I32(if a != b { 1U } else { 0U }))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_lt_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  let result = if a.reinterpret_as_int64() < b.reinterpret_as_int64() {
    1U
  } else {
    0U
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_lt_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I32(if a < b { 1U } else { 0U }))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_gt_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  let result = if a.reinterpret_as_int64() > b.reinterpret_as_int64() {
    1U
  } else {
    0U
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_gt_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I32(if a > b { 1U } else { 0U }))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_le_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  let result = if a.reinterpret_as_int64() <= b.reinterpret_as_int64() {
    1U
  } else {
    0U
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_le_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I32(if a <= b { 1U } else { 0U }))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_ge_s(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  let result = if a.reinterpret_as_int64() >= b.reinterpret_as_int64() {
    1U
  } else {
    0U
  }
  rt.stack.push(Value::I32(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_ge_u(rt : Runtime) -> RetCode {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I32(if a >= b { 1U } else { 0U }))
  rt.pc += 1
  return next_op(rt)
}

// i64 unary operations

///|
#tailcall
fn op_i64_eqz(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  rt.stack.push(Value::I32(if a == 0UL { 1U } else { 0U }))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_clz(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  rt.stack.push(Value::I64(a.clz().to_uint64()))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_ctz(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  rt.stack.push(Value::I64(a.ctz().to_uint64()))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_popcnt(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  rt.stack.push(Value::I64(a.popcnt().to_uint64()))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_extend8_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  let byte = a & 0xFFUL
  let result = if (byte & 0x80UL) != 0UL {
    byte | 0xFFFFFFFFFFFFFF00UL
  } else {
    byte
  }
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_extend16_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  let half = a & 0xFFFFUL
  let result = if (half & 0x8000UL) != 0UL {
    half | 0xFFFFFFFFFFFF0000UL
  } else {
    half
  }
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_extend32_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i64()
  let word = a & 0xFFFFFFFFUL
  let result = if (word & 0x80000000UL) != 0UL {
    word | 0xFFFFFFFF00000000UL
  } else {
    word
  }
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_extend_i32_s(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  let result = a.reinterpret_as_int().to_int64().reinterpret_as_uint64()
  rt.stack.push(Value::I64(result))
  rt.pc += 1
  return next_op(rt)
}

///|
#tailcall
fn op_i64_extend_i32_u(rt : Runtime) -> RetCode {
  let a = rt.pop_i32()
  rt.stack.push(Value::I64(a.to_uint64()))
  rt.pc += 1
  return next_op(rt)
}
