///|
fn empty_module() -> @core.Module {
  {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
}

///|
/// Convert Int to UInt64 for immediate index values in tests
fn idx(value : Int) -> UInt64 {
  value.to_int64().reinterpret_as_uint64()
}

///|
/// Convert UInt to UInt64 for immediate i32 values in tests
fn imm(value : UInt) -> UInt64 {
  value.to_uint64()
}

///|
fn make_runtime(
  stack : Array[Value],
  ops : Array[UInt64],
  memory_size : Int,
) -> Runtime {
  // Convert Value array to UInt64 array and allocate fixed buffer
  let stack64 = stack.map(value_to_stack)
  let stack_len = stack64.length()
  let capacity = if stack_len < 64 { 64 } else { stack_len * 2 }
  let stack_buf = FixedArray::make(capacity, 0UL)
  for i in 0..<stack_len {
    stack_buf[i] = stack64[i]
  }
  let ctx = RuntimeContext::new_with_gc_heap(
    empty_module(),
    Array::make(memory_size, b'\x00'),
    None,
    [],
    [],
    [],
    [],
    [],
  )
  Runtime::{
    ops: FixedArray::from_array(ops),
    stack: stack_buf,
    sp: stack_len,
    bp: 0,
    num_locals: 0,
    pc: 0,
    status: Terminated,
    ctx,
  }
}

///|
fn assert_stack_elem_eq(got : UInt64, expected : Value) -> Unit {
  let exp = value_to_stack(expected)
  if got != exp {
    abort("stack element mismatch: got \{got}, expected \{exp}")
  }
}

///|
fn stack_f32(raw : UInt64) -> Float {
  Float::reinterpret_from_uint((raw & 0xFFFFFFFFUL).to_uint())
}

///|
fn stack_f64(raw : UInt64) -> Double {
  raw.reinterpret_as_double()
}

///|
fn push_value(rt : Runtime, v : Value) -> Runtime {
  rt.stack.unsafe_set(rt.sp, value_to_stack(v))
  rt.sp = rt.sp + 1
  rt
}

///|
fn assert_ok(rt : Runtime) -> Unit {
  if rt.status == Trap {
    abort("expected OK but got Trap: \{rt.ctx.error_detail}")
  }
}

///|
fn assert_trap(rt : Runtime) -> Unit {
  if rt.status != Trap {
    abort("expected Trap but got no trap")
  }
}

///|
fn rotl32(value : UInt, shift : UInt) -> UInt {
  let s = (shift & 31U).reinterpret_as_int()
  if s == 0 {
    value
  } else {
    (value << s) | (value >> (32 - s))
  }
}

///|
fn rotr32(value : UInt, shift : UInt) -> UInt {
  let s = (shift & 31U).reinterpret_as_int()
  if s == 0 {
    value
  } else {
    (value >> s) | (value << (32 - s))
  }
}

///|
fn rotl64(value : UInt64, shift : UInt64) -> UInt64 {
  let s = (shift & 63UL).to_int()
  if s == 0 {
    value
  } else {
    (value << s) | (value >> (64 - s))
  }
}

///|
fn rotr64(value : UInt64, shift : UInt64) -> UInt64 {
  let s = (shift & 63UL).to_int()
  if s == 0 {
    value
  } else {
    (value >> s) | (value << (64 - s))
  }
}

///|
fn clz32(value : UInt) -> UInt {
  let mut count = 0
  let mut mask = 0x80000000U
  while mask != 0U && (value & mask) == 0U {
    count += 1
    mask = mask >> 1
  }
  count.reinterpret_as_uint()
}

///|
fn ctz32(value : UInt) -> UInt {
  let mut count = 0
  let mut mask = 1U
  while mask != 0U && (value & mask) == 0U {
    count += 1
    mask = mask << 1
  }
  count.reinterpret_as_uint()
}

///|
fn popcnt32(value : UInt) -> UInt {
  let mut count = 0
  let mut v = value
  while v != 0U {
    count += (v & 1U).reinterpret_as_int()
    v = v >> 1
  }
  count.reinterpret_as_uint()
}

///|
fn clz64(value : UInt64) -> UInt {
  let mut count = 0
  let mut mask = 0x8000000000000000UL
  while mask != 0UL && (value & mask) == 0UL {
    count += 1
    mask = mask >> 1
  }
  count.reinterpret_as_uint()
}

///|
fn ctz64(value : UInt64) -> UInt {
  let mut count = 0
  let mut mask = 1UL
  while mask != 0UL && (value & mask) == 0UL {
    count += 1
    mask = mask << 1
  }
  count.reinterpret_as_uint()
}

///|
fn popcnt64(value : UInt64) -> UInt {
  let mut count = 0
  let mut v = value
  while v != 0UL {
    count += (v & 1UL).to_int()
    v = v >> 1
  }
  count.reinterpret_as_uint()
}

///|
fn f32_bits(value : Float) -> UInt {
  value.reinterpret_as_uint()
}

///|
fn f64_bits(value : Double) -> UInt64 {
  value.reinterpret_as_uint64()
}

///|
test "ops i32 const and arithmetic" {
  let rt_const = make_runtime([], [imm(0U), imm(123U)], 0)
  let _ = op_i32_const(rt_const)
  assert_ok(rt_const)
  assert_stack_elem_eq(rt_const.stack[0], Value::I32(123U))
  let cases : Array[((Runtime) -> ReturnCode, UInt)] = [
    (op_i32_add, 9U),
    (op_i32_sub, 3U),
    (op_i32_mul, 18U),
    (op_i32_div_s, 2U),
    (op_i32_div_u, 2U),
    (op_i32_rem_s, 0U),
    (op_i32_rem_u, 0U),
    (op_i32_and, 2U),
    (op_i32_or, 7U),
    (op_i32_xor, 5U),
    (op_i32_shl, 48U),
    (op_i32_shr_s, 0U),
    (op_i32_shr_u, 0U),
    (op_i32_rotl, rotl32(6U, 3U)),
    (op_i32_rotr, rotr32(6U, 3U)),
  ]
  for case in cases {
    let (op, expected) = case
    let rt = make_runtime([Value::I32(6U), Value::I32(3U)], [], 0)
    let _ = op(rt)
    assert_ok(rt)
    assert_stack_elem_eq(rt.stack.unsafe_get(0), Value::I32(expected))
  }
}

///|
test "ops i32 compare and unary" {
  let compare_cases : Array[((Runtime) -> ReturnCode, UInt, UInt, UInt)] = [
    (op_i32_eq, 7U, 7U, 1U),
    (op_i32_ne, 7U, 6U, 1U),
    (op_i32_lt_s, 0xFFFFFFFFU, 1U, 1U),
    (op_i32_lt_u, 0xFFFFFFFFU, 1U, 0U),
    (op_i32_gt_s, 1U, 0xFFFFFFFFU, 1U),
    (op_i32_gt_u, 1U, 0xFFFFFFFFU, 0U),
    (op_i32_le_s, 0xFFFFFFFFU, 1U, 1U),
    (op_i32_le_u, 0xFFFFFFFFU, 1U, 0U),
    (op_i32_ge_s, 0xFFFFFFFFU, 1U, 0U),
    (op_i32_ge_u, 0xFFFFFFFFU, 1U, 1U),
  ]
  for case in compare_cases {
    let (op, a, b, expected) = case
    let rt = make_runtime([Value::I32(a), Value::I32(b)], [], 0)
    let _ = op(rt)
    assert_ok(rt)
    assert_stack_elem_eq(rt.stack.unsafe_get(0), Value::I32(expected))
  }
  let rt_eqz = make_runtime([Value::I32(0U)], [], 0)
  let _ = op_i32_eqz(rt_eqz)
  assert_ok(rt_eqz)
  assert_stack_elem_eq(rt_eqz.stack[0], Value::I32(1U))
  let rt_clz = make_runtime([Value::I32(1U)], [], 0)
  let _ = op_i32_clz(rt_clz)
  assert_ok(rt_clz)
  assert_stack_elem_eq(rt_clz.stack[0], Value::I32(clz32(1U)))
  let rt_ctz = make_runtime([Value::I32(8U)], [], 0)
  let _ = op_i32_ctz(rt_ctz)
  assert_ok(rt_ctz)
  assert_stack_elem_eq(rt_ctz.stack[0], Value::I32(ctz32(8U)))
  let rt_popcnt = make_runtime([Value::I32(0xF0F0U)], [], 0)
  let _ = op_i32_popcnt(rt_popcnt)
  assert_ok(rt_popcnt)
  assert_stack_elem_eq(rt_popcnt.stack[0], Value::I32(popcnt32(0xF0F0U)))
  let rt_extend8 = make_runtime([Value::I32(0x000000FFU)], [], 0)
  let _ = op_i32_extend8_s(rt_extend8)
  assert_ok(rt_extend8)
  assert_stack_elem_eq(rt_extend8.stack[0], Value::I32(0xFFFFFFFFU))
  let rt_extend16 = make_runtime([Value::I32(0x00008000U)], [], 0)
  let _ = op_i32_extend16_s(rt_extend16)
  assert_ok(rt_extend16)
  assert_stack_elem_eq(rt_extend16.stack[0], Value::I32(0xFFFF8000U))
  let rt_wrap = make_runtime([Value::I64(0x0000000200000001UL)], [], 0)
  let _ = op_i32_wrap_i64(rt_wrap)
  assert_ok(rt_wrap)
  assert_stack_elem_eq(rt_wrap.stack[0], Value::I32(1U))
  let rt_div_zero = make_runtime([Value::I32(1U), Value::I32(0U)], [], 0)
  let _ = op_i32_div_s(rt_div_zero)
  assert_trap(rt_div_zero)
  let rt_overflow = make_runtime(
    [Value::I32(0x80000000U), Value::I32(0xFFFFFFFFU)],
    [],
    0,
  )
  let _ = op_i32_div_s(rt_overflow)
  assert_trap(rt_overflow)
}

///|
test "ops i64 const and arithmetic" {
  let rt_const = make_runtime([], [imm(0U), imm(3U), imm(2U)], 0)
  let _ = op_i64_const(rt_const)
  assert_ok(rt_const)
  assert_stack_elem_eq(rt_const.stack[0], Value::I64(0x0000000200000003UL))
  let cases : Array[((Runtime) -> ReturnCode, UInt64)] = [
    (op_i64_add, 9UL),
    (op_i64_sub, 3UL),
    (op_i64_mul, 18UL),
    (op_i64_div_s, 2UL),
    (op_i64_div_u, 2UL),
    (op_i64_rem_s, 0UL),
    (op_i64_rem_u, 0UL),
    (op_i64_and, 2UL),
    (op_i64_or, 7UL),
    (op_i64_xor, 5UL),
    (op_i64_shl, 48UL),
    (op_i64_shr_s, 0UL),
    (op_i64_shr_u, 0UL),
    (op_i64_rotl, rotl64(6UL, 3UL)),
    (op_i64_rotr, rotr64(6UL, 3UL)),
  ]
  for case in cases {
    let (op, expected) = case
    let rt = make_runtime([Value::I64(6UL), Value::I64(3UL)], [], 0)
    let _ = op(rt)
    assert_ok(rt)
    assert_stack_elem_eq(rt.stack.unsafe_get(0), Value::I64(expected))
  }
}

///|
test "ops i64 compare and unary" {
  let compare_cases : Array[((Runtime) -> ReturnCode, UInt64, UInt64, UInt)] = [
    (op_i64_eq, 7UL, 7UL, 1U),
    (op_i64_ne, 7UL, 6UL, 1U),
    (op_i64_lt_s, 0xFFFFFFFFFFFFFFFFUL, 1UL, 1U),
    (op_i64_lt_u, 0xFFFFFFFFFFFFFFFFUL, 1UL, 0U),
    (op_i64_gt_s, 1UL, 0xFFFFFFFFFFFFFFFFUL, 1U),
    (op_i64_gt_u, 1UL, 0xFFFFFFFFFFFFFFFFUL, 0U),
    (op_i64_le_s, 0xFFFFFFFFFFFFFFFFUL, 1UL, 1U),
    (op_i64_le_u, 0xFFFFFFFFFFFFFFFFUL, 1UL, 0U),
    (op_i64_ge_s, 0xFFFFFFFFFFFFFFFFUL, 1UL, 0U),
    (op_i64_ge_u, 0xFFFFFFFFFFFFFFFFUL, 1UL, 1U),
  ]
  for case in compare_cases {
    let (op, a, b, expected) = case
    let rt = make_runtime([Value::I64(a), Value::I64(b)], [], 0)
    let _ = op(rt)
    assert_ok(rt)
    assert_stack_elem_eq(rt.stack.unsafe_get(0), Value::I32(expected))
  }
  let rt_eqz = make_runtime([Value::I64(0UL)], [], 0)
  let _ = op_i64_eqz(rt_eqz)
  assert_ok(rt_eqz)
  assert_stack_elem_eq(rt_eqz.stack[0], Value::I32(1U))
  let rt_clz = make_runtime([Value::I64(1UL)], [], 0)
  let _ = op_i64_clz(rt_clz)
  assert_ok(rt_clz)
  assert_stack_elem_eq(rt_clz.stack[0], Value::I64(clz64(1UL).to_uint64()))
  let rt_ctz = make_runtime([Value::I64(8UL)], [], 0)
  let _ = op_i64_ctz(rt_ctz)
  assert_ok(rt_ctz)
  assert_stack_elem_eq(rt_ctz.stack[0], Value::I64(ctz64(8UL).to_uint64()))
  let rt_popcnt = make_runtime([Value::I64(0xF0F0UL)], [], 0)
  let _ = op_i64_popcnt(rt_popcnt)
  assert_ok(rt_popcnt)
  assert_stack_elem_eq(
    rt_popcnt.stack[0],
    Value::I64(popcnt64(0xF0F0UL).to_uint64()),
  )
  let rt_extend8 = make_runtime([Value::I64(0x00000000000000FFUL)], [], 0)
  let _ = op_i64_extend8_s(rt_extend8)
  assert_ok(rt_extend8)
  assert_stack_elem_eq(rt_extend8.stack[0], Value::I64(0xFFFFFFFFFFFFFFFFUL))
  let rt_extend16 = make_runtime([Value::I64(0x0000000000008000UL)], [], 0)
  let _ = op_i64_extend16_s(rt_extend16)
  assert_ok(rt_extend16)
  assert_stack_elem_eq(rt_extend16.stack[0], Value::I64(0xFFFFFFFFFFFF8000UL))
  let rt_extend32 = make_runtime([Value::I64(0x0000000080000000UL)], [], 0)
  let _ = op_i64_extend32_s(rt_extend32)
  assert_ok(rt_extend32)
  assert_stack_elem_eq(rt_extend32.stack[0], Value::I64(0xFFFFFFFF80000000UL))
  let rt_extend_i32_s = make_runtime([Value::I32(0xFFFFFFFFU)], [], 0)
  let _ = op_i64_extend_i32_s(rt_extend_i32_s)
  assert_ok(rt_extend_i32_s)
  assert_stack_elem_eq(
    rt_extend_i32_s.stack[0],
    Value::I64(0xFFFFFFFFFFFFFFFFUL),
  )
  let rt_extend_i32_u = make_runtime([Value::I32(0xFFFFFFFFU)], [], 0)
  let _ = op_i64_extend_i32_u(rt_extend_i32_u)
  assert_ok(rt_extend_i32_u)
  assert_stack_elem_eq(
    rt_extend_i32_u.stack[0],
    Value::I64(0x00000000FFFFFFFFUL),
  )
}

///|
test "ops i32 error paths" {
  let rt_div_zero = make_runtime([Value::I32(1U), Value::I32(0U)], [], 0)
  let _ = op_i32_div_u(rt_div_zero)
  assert_trap(rt_div_zero)
  let rt_rem_s = make_runtime([Value::I32(1U), Value::I32(0U)], [], 0)
  let _ = op_i32_rem_s(rt_rem_s)
  assert_trap(rt_rem_s)
  let rt_rem_u = make_runtime([Value::I32(1U), Value::I32(0U)], [], 0)
  let _ = op_i32_rem_u(rt_rem_u)
  assert_trap(rt_rem_u)
  let rt_lt_false = make_runtime([Value::I32(5U), Value::I32(1U)], [], 0)
  let _ = op_i32_lt_s(rt_lt_false)
  assert_ok(rt_lt_false)
  assert_stack_elem_eq(rt_lt_false.stack[0], Value::I32(0U))
  let rt_gt_false = make_runtime([Value::I32(1U), Value::I32(5U)], [], 0)
  let _ = op_i32_gt_s(rt_gt_false)
  assert_ok(rt_gt_false)
  assert_stack_elem_eq(rt_gt_false.stack[0], Value::I32(0U))
}

///|
test "ops float const and arithmetic" {
  let rt_f32_const = make_runtime([], [imm(0U), imm(0x3F800000U)], 0)
  let _ = op_f32_const(rt_f32_const)
  assert_ok(rt_f32_const)
  assert_stack_elem_eq(rt_f32_const.stack[0], Value::F32(1.0))
  let rt_f64_const = make_runtime(
    [],
    [imm(0U), imm(0x00000000U), imm(0x3FF00000U)],
    0,
  )
  let _ = op_f64_const(rt_f64_const)
  assert_ok(rt_f64_const)
  assert_stack_elem_eq(rt_f64_const.stack[0], Value::F64(1.0))
  let f32_bin_cases : Array[((Runtime) -> ReturnCode, Float, Float, Float)] = [
    (op_f32_add, 6.0, 3.0, 9.0),
    (op_f32_sub, 6.0, 3.0, 3.0),
    (op_f32_mul, 6.0, 3.0, 18.0),
    (op_f32_div, 6.0, 3.0, 2.0),
    (op_f32_min, 6.0, 3.0, 3.0),
    (op_f32_max, 6.0, 3.0, 6.0),
  ]
  for case in f32_bin_cases {
    let (op, a, b, expected) = case
    let rt = make_runtime([Value::F32(a), Value::F32(b)], [], 0)
    let _ = op(rt)
    assert_ok(rt)
    assert_stack_elem_eq(rt.stack.unsafe_get(0), Value::F32(expected))
  }
  let rt_f32_copysign = make_runtime([Value::F32(3.0), Value::F32(-2.0)], [], 0)
  let _ = op_f32_copysign(rt_f32_copysign)
  assert_ok(rt_f32_copysign)
  assert_stack_elem_eq(rt_f32_copysign.stack[0], Value::F32(-3.0))
  let f32_cmp_cases : Array[((Runtime) -> ReturnCode, Float, Float, UInt)] = [
    (op_f32_eq, 3.0, 3.0, 1U),
    (op_f32_ne, 3.0, 2.0, 1U),
    (op_f32_lt, 2.0, 3.0, 1U),
    (op_f32_gt, 3.0, 2.0, 1U),
    (op_f32_le, 2.0, 2.0, 1U),
    (op_f32_ge, 3.0, 2.0, 1U),
  ]
  for case in f32_cmp_cases {
    let (op, a, b, expected) = case
    let rt = make_runtime([Value::F32(a), Value::F32(b)], [], 0)
    let _ = op(rt)
    assert_ok(rt)
    assert_stack_elem_eq(rt.stack.unsafe_get(0), Value::I32(expected))
  }
  let rt_f32_neg = make_runtime([Value::F32(3.0)], [], 0)
  let _ = op_f32_neg(rt_f32_neg)
  assert_ok(rt_f32_neg)
  assert_stack_elem_eq(rt_f32_neg.stack[0], Value::F32(-3.0))
  let rt_f32_abs = make_runtime([Value::F32(-3.0)], [], 0)
  let _ = op_f32_abs(rt_f32_abs)
  assert_ok(rt_f32_abs)
  assert_stack_elem_eq(rt_f32_abs.stack[0], Value::F32(3.0))
  let rt_f32_sqrt = make_runtime([Value::F32(4.0)], [], 0)
  let _ = op_f32_sqrt(rt_f32_sqrt)
  assert_ok(rt_f32_sqrt)
  assert_stack_elem_eq(rt_f32_sqrt.stack.unsafe_get(0), Value::F32(2.0))
  let rt_f32_ceil = make_runtime([Value::F32(1.2)], [], 0)
  let _ = op_f32_ceil(rt_f32_ceil)
  assert_ok(rt_f32_ceil)
  assert_stack_elem_eq(rt_f32_ceil.stack[0], Value::F32(2.0))
  let rt_f32_floor = make_runtime([Value::F32(1.8)], [], 0)
  let _ = op_f32_floor(rt_f32_floor)
  assert_ok(rt_f32_floor)
  assert_stack_elem_eq(rt_f32_floor.stack[0], Value::F32(1.0))
  let rt_f32_trunc = make_runtime([Value::F32(1.8)], [], 0)
  let _ = op_f32_trunc(rt_f32_trunc)
  assert_ok(rt_f32_trunc)
  assert_stack_elem_eq(rt_f32_trunc.stack[0], Value::F32(1.0))
  let rt_f32_nearest = make_runtime([Value::F32(1.2)], [], 0)
  let _ = op_f32_nearest(rt_f32_nearest)
  assert_ok(rt_f32_nearest)
  assert_stack_elem_eq(rt_f32_nearest.stack[0], Value::F32(1.0))
  let f64_bin_cases : Array[((Runtime) -> ReturnCode, Double, Double, Double)] = [
    (op_f64_add, 6.0, 3.0, 9.0),
    (op_f64_sub, 6.0, 3.0, 3.0),
    (op_f64_mul, 6.0, 3.0, 18.0),
    (op_f64_div, 6.0, 3.0, 2.0),
    (op_f64_min, 6.0, 3.0, 3.0),
    (op_f64_max, 6.0, 3.0, 6.0),
  ]
  for case in f64_bin_cases {
    let (op, a, b, expected) = case
    let rt = make_runtime([Value::F64(a), Value::F64(b)], [], 0)
    let _ = op(rt)
    assert_ok(rt)
    assert_stack_elem_eq(rt.stack.unsafe_get(0), Value::F64(expected))
  }
  let rt_f64_copysign = make_runtime([Value::F64(3.0), Value::F64(-2.0)], [], 0)
  let _ = op_f64_copysign(rt_f64_copysign)
  assert_ok(rt_f64_copysign)
  assert_stack_elem_eq(rt_f64_copysign.stack[0], Value::F64(-3.0))
  let f64_cmp_cases : Array[((Runtime) -> ReturnCode, Double, Double, UInt)] = [
    (op_f64_eq, 3.0, 3.0, 1U),
    (op_f64_ne, 3.0, 2.0, 1U),
    (op_f64_lt, 2.0, 3.0, 1U),
    (op_f64_gt, 3.0, 2.0, 1U),
    (op_f64_le, 2.0, 2.0, 1U),
    (op_f64_ge, 3.0, 2.0, 1U),
  ]
  for case in f64_cmp_cases {
    let (op, a, b, expected) = case
    let rt = make_runtime([Value::F64(a), Value::F64(b)], [], 0)
    let _ = op(rt)
    assert_ok(rt)
    assert_stack_elem_eq(rt.stack.unsafe_get(0), Value::I32(expected))
  }
  let rt_f64_neg = make_runtime([Value::F64(3.0)], [], 0)
  let _ = op_f64_neg(rt_f64_neg)
  assert_ok(rt_f64_neg)
  assert_stack_elem_eq(rt_f64_neg.stack[0], Value::F64(-3.0))
  let rt_f64_abs = make_runtime([Value::F64(-3.0)], [], 0)
  let _ = op_f64_abs(rt_f64_abs)
  assert_ok(rt_f64_abs)
  assert_stack_elem_eq(rt_f64_abs.stack[0], Value::F64(3.0))
  let rt_f64_sqrt = make_runtime([Value::F64(4.0)], [], 0)
  let _ = op_f64_sqrt(rt_f64_sqrt)
  assert_ok(rt_f64_sqrt)
  assert_stack_elem_eq(rt_f64_sqrt.stack.unsafe_get(0), Value::F64(2.0))
  let rt_f64_ceil = make_runtime([Value::F64(1.2)], [], 0)
  let _ = op_f64_ceil(rt_f64_ceil)
  assert_ok(rt_f64_ceil)
  assert_stack_elem_eq(rt_f64_ceil.stack[0], Value::F64(2.0))
  let rt_f64_floor = make_runtime([Value::F64(1.8)], [], 0)
  let _ = op_f64_floor(rt_f64_floor)
  assert_ok(rt_f64_floor)
  assert_stack_elem_eq(rt_f64_floor.stack[0], Value::F64(1.0))
  let rt_f64_trunc = make_runtime([Value::F64(1.8)], [], 0)
  let _ = op_f64_trunc(rt_f64_trunc)
  assert_ok(rt_f64_trunc)
  assert_stack_elem_eq(rt_f64_trunc.stack[0], Value::F64(1.0))
  let rt_f64_nearest = make_runtime([Value::F64(1.2)], [], 0)
  let _ = op_f64_nearest(rt_f64_nearest)
  assert_ok(rt_f64_nearest)
  assert_stack_elem_eq(rt_f64_nearest.stack[0], Value::F64(1.0))
}

///|
test "ops float min/max edge cases" {
  let nan_f32 : Float = 0.0 / 0.0
  let nan_f64 : Double = 0.0 / 0.0
  let rt_f32_min_nan = make_runtime(
    [Value::F32(nan_f32), Value::F32(1.0)],
    [],
    0,
  )
  let _ = op_f32_min(rt_f32_min_nan)
  assert_ok(rt_f32_min_nan)
  let rt_f32_min_nan_value = stack_f32(rt_f32_min_nan.stack[0])
  assert_eq(f32_bits(rt_f32_min_nan_value), f32_bits(canonical_nan_f32))
  let rt_f32_max_nan = make_runtime(
    [Value::F32(1.0), Value::F32(nan_f32)],
    [],
    0,
  )
  let _ = op_f32_max(rt_f32_max_nan)
  assert_ok(rt_f32_max_nan)
  let rt_f32_max_nan_value = stack_f32(rt_f32_max_nan.stack[0])
  assert_eq(f32_bits(rt_f32_max_nan_value), f32_bits(canonical_nan_f32))
  let neg_zero_f32 : Float = -0.0
  let pos_zero_f32 : Float = 0.0
  let rt_f32_min_zero = make_runtime(
    [Value::F32(pos_zero_f32), Value::F32(neg_zero_f32)],
    [],
    0,
  )
  let _ = op_f32_min(rt_f32_min_zero)
  assert_ok(rt_f32_min_zero)
  let rt_f32_min_value = stack_f32(rt_f32_min_zero.stack[0])
  assert_eq(f32_bits(rt_f32_min_value), f32_bits(neg_zero_f32))
  let rt_f32_max_zero = make_runtime(
    [Value::F32(neg_zero_f32), Value::F32(pos_zero_f32)],
    [],
    0,
  )
  let _ = op_f32_max(rt_f32_max_zero)
  assert_ok(rt_f32_max_zero)
  let rt_f32_max_value = stack_f32(rt_f32_max_zero.stack[0])
  assert_eq(f32_bits(rt_f32_max_value), f32_bits(pos_zero_f32))
  let rt_f64_min_nan = make_runtime(
    [Value::F64(nan_f64), Value::F64(1.0)],
    [],
    0,
  )
  let _ = op_f64_min(rt_f64_min_nan)
  assert_ok(rt_f64_min_nan)
  let rt_f64_min_nan_value = stack_f64(rt_f64_min_nan.stack[0])
  assert_eq(f64_bits(rt_f64_min_nan_value), f64_bits(canonical_nan_f64))
  let rt_f64_max_nan = make_runtime(
    [Value::F64(1.0), Value::F64(nan_f64)],
    [],
    0,
  )
  let _ = op_f64_max(rt_f64_max_nan)
  assert_ok(rt_f64_max_nan)
  let rt_f64_max_nan_value = stack_f64(rt_f64_max_nan.stack[0])
  assert_eq(f64_bits(rt_f64_max_nan_value), f64_bits(canonical_nan_f64))
  let neg_zero_f64 : Double = -0.0
  let pos_zero_f64 : Double = 0.0
  let rt_f64_min_zero = make_runtime(
    [Value::F64(pos_zero_f64), Value::F64(neg_zero_f64)],
    [],
    0,
  )
  let _ = op_f64_min(rt_f64_min_zero)
  assert_ok(rt_f64_min_zero)
  let rt_f64_min_value = stack_f64(rt_f64_min_zero.stack[0])
  assert_eq(f64_bits(rt_f64_min_value), f64_bits(neg_zero_f64))
  let rt_f64_max_zero = make_runtime(
    [Value::F64(neg_zero_f64), Value::F64(pos_zero_f64)],
    [],
    0,
  )
  let _ = op_f64_max(rt_f64_max_zero)
  assert_ok(rt_f64_max_zero)
  let rt_f64_max_value = stack_f64(rt_f64_max_zero.stack[0])
  assert_eq(f64_bits(rt_f64_max_value), f64_bits(pos_zero_f64))
}

///|
test "ops float conversions" {
  let f32_value : Float = 1.0
  let f64_value : Double = 1.0
  let f32_bits = f32_value.reinterpret_as_uint()
  let f64_bits = f64_value.reinterpret_as_uint64()
  let cases : Array[((Runtime) -> ReturnCode, Array[Value], Value)] = [
    (op_f64_convert_i64_u, [Value::I64(5UL)], Value::F64(5.0)),
    (op_f64_convert_i64_s, [Value::I64(5UL)], Value::F64(5.0)),
    (op_f64_convert_i32_u, [Value::I32(5U)], Value::F64(5.0)),
    (op_f64_convert_i32_s, [Value::I32(5U)], Value::F64(5.0)),
    (op_f64_promote_f32, [Value::F32(3.5)], Value::F64(3.5)),
    (op_f32_demote_f64, [Value::F64(3.5)], Value::F32(3.5)),
    (op_f32_convert_i32_s, [Value::I32(5U)], Value::F32(5.0)),
    (op_f32_convert_i32_u, [Value::I32(5U)], Value::F32(5.0)),
    (op_f32_convert_i64_s, [Value::I64(5UL)], Value::F32(5.0)),
    (op_f32_convert_i64_u, [Value::I64(5UL)], Value::F32(5.0)),
    (op_i64_trunc_f64_s, [Value::F64(5.0)], Value::I64(5UL)),
    (op_i64_trunc_f64_u, [Value::F64(5.0)], Value::I64(5UL)),
    (op_i32_trunc_f32_s, [Value::F32(5.0)], Value::I32(5U)),
    (op_i32_trunc_f32_u, [Value::F32(5.0)], Value::I32(5U)),
    (op_i32_trunc_f64_s, [Value::F64(5.0)], Value::I32(5U)),
    (op_i32_trunc_f64_u, [Value::F64(5.0)], Value::I32(5U)),
    (op_i64_trunc_f32_s, [Value::F32(5.0)], Value::I64(5UL)),
    (op_i64_trunc_f32_u, [Value::F32(5.0)], Value::I64(5UL)),
    (op_i32_trunc_sat_f32_s, [Value::F32(5.0)], Value::I32(5U)),
    (op_i32_trunc_sat_f32_u, [Value::F32(5.0)], Value::I32(5U)),
    (op_i32_trunc_sat_f64_s, [Value::F64(5.0)], Value::I32(5U)),
    (op_i32_trunc_sat_f64_u, [Value::F64(5.0)], Value::I32(5U)),
    (op_i64_trunc_sat_f32_s, [Value::F32(5.0)], Value::I64(5UL)),
    (op_i64_trunc_sat_f32_u, [Value::F32(5.0)], Value::I64(5UL)),
    (op_i64_trunc_sat_f64_s, [Value::F64(5.0)], Value::I64(5UL)),
    (op_i64_trunc_sat_f64_u, [Value::F64(5.0)], Value::I64(5UL)),
    (op_i32_reinterpret_f32, [Value::F32(1.0)], Value::I32(f32_bits)),
    (op_i64_reinterpret_f64, [Value::F64(1.0)], Value::I64(f64_bits)),
    (op_f32_reinterpret_i32, [Value::I32(f32_bits)], Value::F32(1.0)),
    (op_f64_reinterpret_i64, [Value::I64(f64_bits)], Value::F64(1.0)),
  ]
  for case in cases {
    let (op, stack, expected) = case
    let rt = make_runtime(stack, [], 0)
    let _ = op(rt)
    assert_ok(rt)
    assert_stack_elem_eq(rt.stack.unsafe_get(0), expected)
  }
  let rt_nan = make_runtime([Value::F64(0.0 / 0.0)], [], 0)
  let _ = op_i64_trunc_f64_s(rt_nan)
  assert_trap(rt_nan)
}

///|
test "ops trunc sat f64 edge cases" {
  let rt_nan = make_runtime([Value::F64(0.0 / 0.0)], [], 0)
  let _ = op_i64_trunc_sat_f64_s(rt_nan)
  assert_ok(rt_nan)
  assert_stack_elem_eq(rt_nan.stack[0], Value::I64(0UL))
  let rt_over = make_runtime([Value::F64(9223372036854775808.0)], [], 0)
  let _ = op_i64_trunc_sat_f64_s(rt_over)
  assert_ok(rt_over)
  assert_stack_elem_eq(rt_over.stack[0], Value::I64(0x7FFFFFFFFFFFFFFFUL))
  let rt_under = make_runtime([Value::F64(-9223372036854775809.0)], [], 0)
  let _ = op_i64_trunc_sat_f64_s(rt_under)
  assert_ok(rt_under)
  assert_stack_elem_eq(rt_under.stack[0], Value::I64(0x8000000000000000UL))
  let rt_nan_u = make_runtime([Value::F64(0.0 / 0.0)], [], 0)
  let _ = op_i64_trunc_sat_f64_u(rt_nan_u)
  assert_ok(rt_nan_u)
  assert_stack_elem_eq(rt_nan_u.stack[0], Value::I64(0UL))
  let rt_over_u = make_runtime([Value::F64(18446744073709551616.0)], [], 0)
  let _ = op_i64_trunc_sat_f64_u(rt_over_u)
  assert_ok(rt_over_u)
  assert_stack_elem_eq(rt_over_u.stack[0], Value::I64(0xFFFFFFFFFFFFFFFFUL))
  let rt_under_u = make_runtime([Value::F64(-1.0)], [], 0)
  let _ = op_i64_trunc_sat_f64_u(rt_under_u)
  assert_ok(rt_under_u)
  assert_stack_elem_eq(rt_under_u.stack[0], Value::I64(0UL))
}

///|
test "ops memory load/store and size" {
  let ops = [idx(0), idx(0)]
  let rt = make_runtime([], ops, 16)
  let rt = push_value(rt, Value::I32(0U))
  let rt = push_value(rt, Value::I32(0x11223344U))
  let _ = op_i32_store(rt)
  assert_ok(rt)
  let rt = { ..rt, sp: 0, pc: 0 }
  let rt = push_value(rt, Value::I32(0U))
  let _ = op_i32_load(rt)
  assert_ok(rt)
  assert_stack_elem_eq(rt.stack.unsafe_get(0), Value::I32(0x11223344U))
  rt.ctx.memory[0] = 0xFFU.to_byte()
  let rt = { ..rt, sp: 0, pc: 0 }
  let rt = push_value(rt, Value::I32(0U))
  let _ = op_i32_load8_s(rt)
  assert_ok(rt)
  assert_stack_elem_eq(rt.stack.unsafe_get(0), Value::I32(0xFFFFFFFFU))
  let rt = { ..rt, sp: 0, pc: 0 }
  let rt = push_value(rt, Value::I32(0U))
  let _ = op_i32_load8_u(rt)
  assert_ok(rt)
  assert_stack_elem_eq(rt.stack.unsafe_get(0), Value::I32(255U))
  rt.ctx.memory[0] = 0x00U.to_byte()
  rt.ctx.memory[1] = 0x80U.to_byte()
  let rt = { ..rt, sp: 0, pc: 0 }
  let rt = push_value(rt, Value::I32(0U))
  let _ = op_i32_load16_s(rt)
  assert_ok(rt)
  assert_stack_elem_eq(rt.stack.unsafe_get(0), Value::I32(0xFFFF8000U))
  let rt = { ..rt, sp: 0, pc: 0 }
  let rt = push_value(rt, Value::I32(0U))
  let _ = op_i32_load16_u(rt)
  assert_ok(rt)
  assert_stack_elem_eq(rt.stack.unsafe_get(0), Value::I32(0x8000U))
  let rt_size = make_runtime([], [], 65536)
  let _ = op_memory_size(rt_size)
  assert_ok(rt_size)
  assert_stack_elem_eq(rt_size.stack.unsafe_get(0), Value::I32(1U))
  let stack_grow = FixedArray::make(64, 0UL)
  stack_grow[0] = 1UL // i32(1) as UInt64
  let ctx_grow = RuntimeContext::new_with_gc_heap(
    empty_module(),
    Array::make(65536, b'\x00'),
    Some(2UL),
    [],
    [],
    [],
    [],
    [],
  )
  let rt_grow = Runtime::{
    ops: FixedArray::from_array([]),
    stack: stack_grow,
    sp: 1,
    bp: 0,
    num_locals: 0,
    pc: 0,
    status: Terminated,
    ctx: ctx_grow,
  }
  let _ = op_memory_grow(rt_grow)
  assert_ok(rt_grow)
  assert_stack_elem_eq(rt_grow.stack.unsafe_get(0), Value::I32(1U))
}

///|
test "ops memory out of bounds and bulk ops" {
  let rt_oob = make_runtime([], [idx(0), idx(8)], 8)
  let rt_oob = push_value(rt_oob, Value::I32(0U))
  let _ = op_i32_load(rt_oob)
  assert_trap(rt_oob)
  let rt_oob_store = make_runtime([], [idx(0), idx(8)], 8)
  let rt_oob_store = push_value(rt_oob_store, Value::I32(0U))
  let rt_oob_store = push_value(rt_oob_store, Value::I32(1U))
  let _ = op_i32_store(rt_oob_store)
  assert_trap(rt_oob_store)
  let rt_i64 = make_runtime([], [idx(0), idx(0)], 16)
  let rt_i64 = push_value(rt_i64, Value::I32(0U))
  let rt_i64 = push_value(rt_i64, Value::I64(0x1122334455667788UL))
  let _ = op_i64_store(rt_i64)
  assert_ok(rt_i64)
  let rt_i64 = { ..rt_i64, sp: 0, pc: 0 }
  let rt_i64 = push_value(rt_i64, Value::I32(0U))
  let _ = op_i64_load(rt_i64)
  assert_ok(rt_i64)
  assert_stack_elem_eq(
    rt_i64.stack.unsafe_get(0),
    Value::I64(0x1122334455667788UL),
  )
  let rt_copy = make_runtime([], [], 8)
  rt_copy.ctx.memory[0] = 1U.to_byte()
  rt_copy.ctx.memory[1] = 2U.to_byte()
  rt_copy.ctx.memory[2] = 3U.to_byte()
  let rt_copy = push_value(rt_copy, Value::I32(0U))
  let rt_copy = push_value(rt_copy, Value::I32(0U))
  let rt_copy = push_value(rt_copy, Value::I32(3U))
  let _ = op_memory_copy(rt_copy)
  assert_ok(rt_copy)
  assert_eq(rt_copy.ctx.memory[0], 1U.to_byte())
  assert_eq(rt_copy.ctx.memory[1], 2U.to_byte())
  let rt_fill = make_runtime([], [], 8)
  let rt_fill = push_value(rt_fill, Value::I32(0U))
  let rt_fill = push_value(rt_fill, Value::I32(0x7FU))
  let rt_fill = push_value(rt_fill, Value::I32(3U))
  let _ = op_memory_fill(rt_fill)
  assert_ok(rt_fill)
  assert_eq(rt_fill.ctx.memory[0], 0x7FU.to_byte())
  assert_eq(rt_fill.ctx.memory[2], 0x7FU.to_byte())
  let stack_init = FixedArray::make(64, 0UL)
  stack_init[0] = 0UL
  stack_init[1] = 0UL
  stack_init[2] = 2UL // i32 values as UInt64
  let ctx_init = RuntimeContext::new_with_gc_heap(
    empty_module(),
    Array::make(4, b'\x00'),
    None,
    [],
    [],
    [],
    [[1U.to_byte(), 2U.to_byte(), 3U.to_byte()]],
    [],
  )
  let rt_init = Runtime::{
    ops: FixedArray::from_array([idx(0), idx(0)]),
    stack: stack_init,
    sp: 3,
    bp: 0,
    num_locals: 0,
    pc: 0,
    status: Terminated,
    ctx: ctx_init,
  }
  let _ = op_memory_init(rt_init)
  assert_ok(rt_init)
  assert_eq(rt_init.ctx.memory[0], 1U.to_byte())
  assert_eq(rt_init.ctx.memory[1], 2U.to_byte())
  let ctx_drop = RuntimeContext::new_with_gc_heap(
    empty_module(),
    Array::make(1, b'\x00'),
    None,
    [],
    [],
    [],
    [[1U.to_byte()]],
    [],
  )
  let rt_drop = Runtime::{
    ops: FixedArray::from_array([idx(0), idx(0)]),
    stack: FixedArray::make(64, 0UL),
    sp: 0,
    bp: 0,
    num_locals: 0,
    pc: 0,
    status: Terminated,
    ctx: ctx_drop,
  }
  let _ = op_data_drop(rt_drop)
  assert_ok(rt_drop)
  assert_eq(rt_drop.ctx.data_segments[0].length(), 0)
}

///|
test "compile helpers canonicalize and counts" {
  let nan_f32 : Float = 0.0 / 0.0
  let nan_f64 : Double = 0.0 / 0.0
  assert_eq(f32_bits(canonicalize_f32(nan_f32)), f32_bits(canonical_nan_f32))
  assert_eq(f64_bits(canonicalize_f64(nan_f64)), f64_bits(canonical_nan_f64))
  let module_ : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [
      { module_: b"m", name: b"f", desc: Func(0U) },
      {
        module_: b"m",
        name: b"mem",
        desc: Mem({
          limits: { min: 1UL, max: None },
          shared: false,
          memory64: false,
        }),
      },
    ],
    exports: [],
    codes: [],
  }
  assert_eq(count_imported_funcs(module_), 1)
  assert_eq(get_func_type_idx(module_, 0, 1), 0)
  assert_eq(get_func_type_idx(module_, 2, 1), -1)
  let module_funcs : @core.Module = {
    types: [],
    type_groups: [],
    customs: [],
    funcs: [0U, 1U],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
  assert_eq(get_func_type_idx(module_funcs, 1, 0), 1)
}

///|
test "compile helpers pop arguments" {
  let rt = make_runtime([Value::I32(1U), Value::I32(2U), Value::I32(3U)], [], 0)
  let func_type : @core.FuncType = { params: [I32, I32], results: [] }
  let { rt, args } = pop_arguments(rt, func_type)
  assert_eq(args[0], Value::I32(2U))
  assert_eq(args[1], Value::I32(3U))
  assert_eq(rt.sp, 1)
}

///|
test "compile context stack ops" {
  let ctx = CompileCtx::new(0)
  ctx.push_type(I32)
  ctx.pop_type()
  ctx.push_types([I32, I64])
  ctx.pop_types(2)
}

///|
test "RuntimeError from_detail" {
  // Test RuntimeError::from_detail helper
  match RuntimeError::from_detail("division by zero") {
    RuntimeError::DivisionByZero => ()
    _ => abort("expected DivisionByZero")
  }
  match RuntimeError::from_detail("integer overflow") {
    RuntimeError::IntegerOverflow => ()
    _ => abort("expected IntegerOverflow")
  }
  match RuntimeError::from_detail("out of bounds memory access") {
    RuntimeError::MemoryOutOfBounds => ()
    _ => abort("expected MemoryOutOfBounds")
  }
  match RuntimeError::from_detail("unreachable executed") {
    RuntimeError::Unreachable => ()
    _ => abort("expected Unreachable")
  }
  match RuntimeError::from_detail("stack overflow") {
    RuntimeError::StackOverflow => ()
    _ => abort("expected StackOverflow")
  }
  match RuntimeError::from_detail("some other error") {
    RuntimeError::InvalidType(_) => ()
    _ => abort("expected InvalidType")
  }
}
