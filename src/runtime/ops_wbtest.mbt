///|
fn empty_module() -> @core.Module {
  {
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    elems: [],
    datas: [],
    start: None,
    imports: [],
    exports: [],
    codes: [],
  }
}

///|
fn make_runtime(
  stack : Array[Value],
  ops : Array[MInstr],
  memory_size : Int,
) -> Runtime {
  // Convert Value array to UInt64 array
  let stack64 = stack.map(value_to_stack)
  Runtime::{
    module_: empty_module(),
    ops,
    stack: stack64,
    sp: 0,
    num_locals: 0,
    locals: [],
    pc: 0,
    running: false,
    call_stack: [],
    memory: Array::make(memory_size, b'\x00'),
    memory_max: None,
    globals: [],
    tables: [],
    imported_funcs: [],
    data_segments: [],
    error_detail: "",
  }
}

///|
fn assert_stack_eq(stack : Array[UInt64], expected : Array[Value]) -> Unit {
  if stack.length() != expected.length() {
    abort("stack length mismatch: got \{stack.length()}, expected \{expected.length()}")
  }
  for i in 0..<stack.length() {
    let got = stack[i]
    let exp = value_to_stack(expected[i])
    if got != exp {
      abort("stack[\{i}] mismatch: got \{got}, expected \{exp}")
    }
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
fn push_value(stack : Array[UInt64], v : Value) -> Unit {
  stack.push(value_to_stack(v))
}

///|
fn assert_ok(ret : RetCode) -> Unit {
  if ret != OK {
    abort("expected OK")
  }
}

///|
fn assert_ret(ret : RetCode, expected : RetCode) -> Unit {
  if ret != expected {
    abort("unexpected return code")
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
  let s = (shift & 63UL).reinterpret_as_int64().to_int()
  if s == 0 {
    value
  } else {
    (value << s) | (value >> (64 - s))
  }
}

///|
fn rotr64(value : UInt64, shift : UInt64) -> UInt64 {
  let s = (shift & 63UL).reinterpret_as_int64().to_int()
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
    count += (v & 1UL).reinterpret_as_int64().to_int()
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
  let rt_const = make_runtime([], [ImmediateI32(0U), ImmediateI32(123U)], 0)
  let ret_const = op_i32_const(rt_const)
  assert_ok(ret_const)
  assert_stack_elem_eq(rt_const.stack[0], Value::I32(123U))
  let cases : Array[((Runtime) -> RetCode, UInt)] = [
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
    let ret = op(rt)
    assert_ok(ret)
    assert_stack_elem_eq(rt.stack[0], Value::I32(expected))
  }
}

///|
test "ops i32 compare and unary" {
  let compare_cases : Array[((Runtime) -> RetCode, UInt, UInt, UInt)] = [
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
    let ret = op(rt)
    assert_ok(ret)
    assert_stack_elem_eq(rt.stack[0], Value::I32(expected))
  }
  let rt_eqz = make_runtime([Value::I32(0U)], [], 0)
  let ret_eqz = op_i32_eqz(rt_eqz)
  assert_ok(ret_eqz)
  assert_stack_elem_eq(rt_eqz.stack[0], Value::I32(1U))
  let rt_clz = make_runtime([Value::I32(1U)], [], 0)
  let ret_clz = op_i32_clz(rt_clz)
  assert_ok(ret_clz)
  assert_stack_elem_eq(rt_clz.stack[0], Value::I32(clz32(1U)))
  let rt_ctz = make_runtime([Value::I32(8U)], [], 0)
  let ret_ctz = op_i32_ctz(rt_ctz)
  assert_ok(ret_ctz)
  assert_stack_elem_eq(rt_ctz.stack[0], Value::I32(ctz32(8U)))
  let rt_popcnt = make_runtime([Value::I32(0xF0F0U)], [], 0)
  let ret_popcnt = op_i32_popcnt(rt_popcnt)
  assert_ok(ret_popcnt)
  assert_stack_elem_eq(rt_popcnt.stack[0], Value::I32(popcnt32(0xF0F0U)))
  let rt_extend8 = make_runtime([Value::I32(0x000000FFU)], [], 0)
  let ret_extend8 = op_i32_extend8_s(rt_extend8)
  assert_ok(ret_extend8)
  assert_stack_elem_eq(rt_extend8.stack[0], Value::I32(0xFFFFFFFFU))
  let rt_extend16 = make_runtime([Value::I32(0x00008000U)], [], 0)
  let ret_extend16 = op_i32_extend16_s(rt_extend16)
  assert_ok(ret_extend16)
  assert_stack_elem_eq(rt_extend16.stack[0], Value::I32(0xFFFF8000U))
  let rt_wrap = make_runtime([Value::I64(0x0000000200000001UL)], [], 0)
  let ret_wrap = op_i32_wrap_i64(rt_wrap)
  assert_ok(ret_wrap)
  assert_stack_elem_eq(rt_wrap.stack[0], Value::I32(1U))
  let rt_div_zero = make_runtime([Value::I32(1U), Value::I32(0U)], [], 0)
  assert_ret(op_i32_div_s(rt_div_zero), DivisionByZero)
  let rt_overflow = make_runtime(
    [Value::I32(0x80000000U), Value::I32(0xFFFFFFFFU)],
    [],
    0,
  )
  assert_ret(op_i32_div_s(rt_overflow), IntegerOverflow)
}

///|
test "ops i64 const and arithmetic" {
  let rt_const = make_runtime(
    [],
    [ImmediateI32(0U), ImmediateI32(3U), ImmediateI32(2U)],
    0,
  )
  let ret_const = op_i64_const(rt_const)
  assert_ok(ret_const)
  assert_stack_elem_eq(rt_const.stack[0], Value::I64(0x0000000200000003UL))
  let cases : Array[((Runtime) -> RetCode, UInt64)] = [
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
    let ret = op(rt)
    assert_ok(ret)
    assert_stack_elem_eq(rt.stack[0], Value::I64(expected))
  }
}

///|
test "ops i64 compare and unary" {
  let compare_cases : Array[((Runtime) -> RetCode, UInt64, UInt64, UInt)] = [
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
    let ret = op(rt)
    assert_ok(ret)
    assert_stack_elem_eq(rt.stack[0], Value::I32(expected))
  }
  let rt_eqz = make_runtime([Value::I64(0UL)], [], 0)
  let ret_eqz = op_i64_eqz(rt_eqz)
  assert_ok(ret_eqz)
  assert_stack_elem_eq(rt_eqz.stack[0], Value::I32(1U))
  let rt_clz = make_runtime([Value::I64(1UL)], [], 0)
  let ret_clz = op_i64_clz(rt_clz)
  assert_ok(ret_clz)
  assert_stack_elem_eq(rt_clz.stack[0], Value::I64(clz64(1UL).to_uint64()))
  let rt_ctz = make_runtime([Value::I64(8UL)], [], 0)
  let ret_ctz = op_i64_ctz(rt_ctz)
  assert_ok(ret_ctz)
  assert_stack_elem_eq(rt_ctz.stack[0], Value::I64(ctz64(8UL).to_uint64()))
  let rt_popcnt = make_runtime([Value::I64(0xF0F0UL)], [], 0)
  let ret_popcnt = op_i64_popcnt(rt_popcnt)
  assert_ok(ret_popcnt)
  assert_stack_elem_eq(rt_popcnt.stack[0], Value::I64(popcnt64(0xF0F0UL).to_uint64()))
  let rt_extend8 = make_runtime([Value::I64(0x00000000000000FFUL)], [], 0)
  let ret_extend8 = op_i64_extend8_s(rt_extend8)
  assert_ok(ret_extend8)
  assert_stack_elem_eq(rt_extend8.stack[0], Value::I64(0xFFFFFFFFFFFFFFFFUL))
  let rt_extend16 = make_runtime([Value::I64(0x0000000000008000UL)], [], 0)
  let ret_extend16 = op_i64_extend16_s(rt_extend16)
  assert_ok(ret_extend16)
  assert_stack_elem_eq(rt_extend16.stack[0], Value::I64(0xFFFFFFFFFFFF8000UL))
  let rt_extend32 = make_runtime([Value::I64(0x0000000080000000UL)], [], 0)
  let ret_extend32 = op_i64_extend32_s(rt_extend32)
  assert_ok(ret_extend32)
  assert_stack_elem_eq(rt_extend32.stack[0], Value::I64(0xFFFFFFFF80000000UL))
  let rt_extend_i32_s = make_runtime([Value::I32(0xFFFFFFFFU)], [], 0)
  let ret_extend_i32_s = op_i64_extend_i32_s(rt_extend_i32_s)
  assert_ok(ret_extend_i32_s)
  assert_stack_elem_eq(rt_extend_i32_s.stack[0], Value::I64(0xFFFFFFFFFFFFFFFFUL))
  let rt_extend_i32_u = make_runtime([Value::I32(0xFFFFFFFFU)], [], 0)
  let ret_extend_i32_u = op_i64_extend_i32_u(rt_extend_i32_u)
  assert_ok(ret_extend_i32_u)
  assert_stack_elem_eq(rt_extend_i32_u.stack[0], Value::I64(0x00000000FFFFFFFFUL))
}

///|
test "ops i32 error paths" {
  let rt_div_zero = make_runtime([Value::I32(1U), Value::I32(0U)], [], 0)
  assert_ret(op_i32_div_u(rt_div_zero), DivisionByZero)
  let rt_rem_s = make_runtime([Value::I32(1U), Value::I32(0U)], [], 0)
  assert_ret(op_i32_rem_s(rt_rem_s), DivisionByZero)
  let rt_rem_u = make_runtime([Value::I32(1U), Value::I32(0U)], [], 0)
  assert_ret(op_i32_rem_u(rt_rem_u), DivisionByZero)
  let rt_lt_false = make_runtime([Value::I32(5U), Value::I32(1U)], [], 0)
  assert_ok(op_i32_lt_s(rt_lt_false))
  assert_stack_elem_eq(rt_lt_false.stack[0], Value::I32(0U))
  let rt_gt_false = make_runtime([Value::I32(1U), Value::I32(5U)], [], 0)
  assert_ok(op_i32_gt_s(rt_gt_false))
  assert_stack_elem_eq(rt_gt_false.stack[0], Value::I32(0U))
}

///|
test "ops float const and arithmetic" {
  let rt_f32_const = make_runtime(
    [],
    [ImmediateI32(0U), ImmediateI32(0x3F800000U)],
    0,
  )
  assert_ok(op_f32_const(rt_f32_const))
  assert_stack_elem_eq(rt_f32_const.stack[0], Value::F32(1.0))
  let rt_f64_const = make_runtime(
    [],
    [ImmediateI32(0U), ImmediateI32(0x00000000U), ImmediateI32(0x3FF00000U)],
    0,
  )
  assert_ok(op_f64_const(rt_f64_const))
  assert_stack_elem_eq(rt_f64_const.stack[0], Value::F64(1.0))
  let f32_bin_cases : Array[((Runtime) -> RetCode, Float, Float, Float)] = [
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
    let ret = op(rt)
    assert_ok(ret)
    assert_stack_elem_eq(rt.stack[0], Value::F32(expected))
  }
  let rt_f32_copysign = make_runtime([Value::F32(3.0), Value::F32(-2.0)], [], 0)
  assert_ok(op_f32_copysign(rt_f32_copysign))
  assert_stack_elem_eq(rt_f32_copysign.stack[0], Value::F32(-3.0))
  let f32_cmp_cases : Array[((Runtime) -> RetCode, Float, Float, UInt)] = [
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
    let ret = op(rt)
    assert_ok(ret)
    assert_stack_elem_eq(rt.stack[0], Value::I32(expected))
  }
  let rt_f32_neg = make_runtime([Value::F32(3.0)], [], 0)
  assert_ok(op_f32_neg(rt_f32_neg))
  assert_stack_elem_eq(rt_f32_neg.stack[0], Value::F32(-3.0))
  let rt_f32_abs = make_runtime([Value::F32(-3.0)], [], 0)
  assert_ok(op_f32_abs(rt_f32_abs))
  assert_stack_elem_eq(rt_f32_abs.stack[0], Value::F32(3.0))
  let rt_f32_sqrt = make_runtime([Value::F32(4.0)], [], 0)
  assert_ok(op_f32_sqrt(rt_f32_sqrt))
  assert_stack_elem_eq(rt_f32_sqrt.stack[0], Value::F32(2.0))
  let rt_f32_ceil = make_runtime([Value::F32(1.2)], [], 0)
  assert_ok(op_f32_ceil(rt_f32_ceil))
  assert_stack_elem_eq(rt_f32_ceil.stack[0], Value::F32(2.0))
  let rt_f32_floor = make_runtime([Value::F32(1.8)], [], 0)
  assert_ok(op_f32_floor(rt_f32_floor))
  assert_stack_elem_eq(rt_f32_floor.stack[0], Value::F32(1.0))
  let rt_f32_trunc = make_runtime([Value::F32(1.8)], [], 0)
  assert_ok(op_f32_trunc(rt_f32_trunc))
  assert_stack_elem_eq(rt_f32_trunc.stack[0], Value::F32(1.0))
  let rt_f32_nearest = make_runtime([Value::F32(1.2)], [], 0)
  assert_ok(op_f32_nearest(rt_f32_nearest))
  assert_stack_elem_eq(rt_f32_nearest.stack[0], Value::F32(1.0))
  let f64_bin_cases : Array[((Runtime) -> RetCode, Double, Double, Double)] = [
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
    let ret = op(rt)
    assert_ok(ret)
    assert_stack_elem_eq(rt.stack[0], Value::F64(expected))
  }
  let rt_f64_copysign = make_runtime([Value::F64(3.0), Value::F64(-2.0)], [], 0)
  assert_ok(op_f64_copysign(rt_f64_copysign))
  assert_stack_elem_eq(rt_f64_copysign.stack[0], Value::F64(-3.0))
  let f64_cmp_cases : Array[((Runtime) -> RetCode, Double, Double, UInt)] = [
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
    let ret = op(rt)
    assert_ok(ret)
    assert_stack_elem_eq(rt.stack[0], Value::I32(expected))
  }
  let rt_f64_neg = make_runtime([Value::F64(3.0)], [], 0)
  assert_ok(op_f64_neg(rt_f64_neg))
  assert_stack_elem_eq(rt_f64_neg.stack[0], Value::F64(-3.0))
  let rt_f64_abs = make_runtime([Value::F64(-3.0)], [], 0)
  assert_ok(op_f64_abs(rt_f64_abs))
  assert_stack_elem_eq(rt_f64_abs.stack[0], Value::F64(3.0))
  let rt_f64_sqrt = make_runtime([Value::F64(4.0)], [], 0)
  assert_ok(op_f64_sqrt(rt_f64_sqrt))
  assert_stack_elem_eq(rt_f64_sqrt.stack[0], Value::F64(2.0))
  let rt_f64_ceil = make_runtime([Value::F64(1.2)], [], 0)
  assert_ok(op_f64_ceil(rt_f64_ceil))
  assert_stack_elem_eq(rt_f64_ceil.stack[0], Value::F64(2.0))
  let rt_f64_floor = make_runtime([Value::F64(1.8)], [], 0)
  assert_ok(op_f64_floor(rt_f64_floor))
  assert_stack_elem_eq(rt_f64_floor.stack[0], Value::F64(1.0))
  let rt_f64_trunc = make_runtime([Value::F64(1.8)], [], 0)
  assert_ok(op_f64_trunc(rt_f64_trunc))
  assert_stack_elem_eq(rt_f64_trunc.stack[0], Value::F64(1.0))
  let rt_f64_nearest = make_runtime([Value::F64(1.2)], [], 0)
  assert_ok(op_f64_nearest(rt_f64_nearest))
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
  assert_ok(op_f32_min(rt_f32_min_nan))
  let rt_f32_min_nan_value = stack_f32(rt_f32_min_nan.stack[0])
  assert_eq(f32_bits(rt_f32_min_nan_value), f32_bits(canonical_nan_f32))
  let rt_f32_max_nan = make_runtime(
    [Value::F32(1.0), Value::F32(nan_f32)],
    [],
    0,
  )
  assert_ok(op_f32_max(rt_f32_max_nan))
  let rt_f32_max_nan_value = stack_f32(rt_f32_max_nan.stack[0])
  assert_eq(f32_bits(rt_f32_max_nan_value), f32_bits(canonical_nan_f32))
  let neg_zero_f32 : Float = -0.0
  let pos_zero_f32 : Float = 0.0
  let rt_f32_min_zero = make_runtime(
    [Value::F32(pos_zero_f32), Value::F32(neg_zero_f32)],
    [],
    0,
  )
  assert_ok(op_f32_min(rt_f32_min_zero))
  let rt_f32_min_value = stack_f32(rt_f32_min_zero.stack[0])
  assert_eq(f32_bits(rt_f32_min_value), f32_bits(neg_zero_f32))
  let rt_f32_max_zero = make_runtime(
    [Value::F32(neg_zero_f32), Value::F32(pos_zero_f32)],
    [],
    0,
  )
  assert_ok(op_f32_max(rt_f32_max_zero))
  let rt_f32_max_value = stack_f32(rt_f32_max_zero.stack[0])
  assert_eq(f32_bits(rt_f32_max_value), f32_bits(pos_zero_f32))
  let rt_f64_min_nan = make_runtime(
    [Value::F64(nan_f64), Value::F64(1.0)],
    [],
    0,
  )
  assert_ok(op_f64_min(rt_f64_min_nan))
  let rt_f64_min_nan_value = stack_f64(rt_f64_min_nan.stack[0])
  assert_eq(f64_bits(rt_f64_min_nan_value), f64_bits(canonical_nan_f64))
  let rt_f64_max_nan = make_runtime(
    [Value::F64(1.0), Value::F64(nan_f64)],
    [],
    0,
  )
  assert_ok(op_f64_max(rt_f64_max_nan))
  let rt_f64_max_nan_value = stack_f64(rt_f64_max_nan.stack[0])
  assert_eq(f64_bits(rt_f64_max_nan_value), f64_bits(canonical_nan_f64))
  let neg_zero_f64 : Double = -0.0
  let pos_zero_f64 : Double = 0.0
  let rt_f64_min_zero = make_runtime(
    [Value::F64(pos_zero_f64), Value::F64(neg_zero_f64)],
    [],
    0,
  )
  assert_ok(op_f64_min(rt_f64_min_zero))
  let rt_f64_min_value = stack_f64(rt_f64_min_zero.stack[0])
  assert_eq(f64_bits(rt_f64_min_value), f64_bits(neg_zero_f64))
  let rt_f64_max_zero = make_runtime(
    [Value::F64(neg_zero_f64), Value::F64(pos_zero_f64)],
    [],
    0,
  )
  assert_ok(op_f64_max(rt_f64_max_zero))
  let rt_f64_max_value = stack_f64(rt_f64_max_zero.stack[0])
  assert_eq(f64_bits(rt_f64_max_value), f64_bits(pos_zero_f64))
}

///|
test "ops float conversions" {
  let f32_value : Float = 1.0
  let f64_value : Double = 1.0
  let f32_bits = f32_value.reinterpret_as_uint()
  let f64_bits = f64_value.reinterpret_as_uint64()
  let cases : Array[((Runtime) -> RetCode, Array[Value], Value)] = [
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
    let ret = op(rt)
    assert_ok(ret)
    assert_stack_elem_eq(rt.stack[0], expected)
  }
  let rt_nan = make_runtime([Value::F64(0.0 / 0.0)], [], 0)
  assert_ret(op_i64_trunc_f64_s(rt_nan), IntegerOverflow)
}

///|
test "ops trunc sat f64 edge cases" {
  let rt_nan = make_runtime([Value::F64(0.0 / 0.0)], [], 0)
  assert_ok(op_i64_trunc_sat_f64_s(rt_nan))
  assert_stack_elem_eq(rt_nan.stack[0], Value::I64(0UL))
  let rt_over = make_runtime([Value::F64(9223372036854775808.0)], [], 0)
  assert_ok(op_i64_trunc_sat_f64_s(rt_over))
  assert_stack_elem_eq(rt_over.stack[0], Value::I64(0x7FFFFFFFFFFFFFFFUL))
  let rt_under = make_runtime([Value::F64(-9223372036854775809.0)], [], 0)
  assert_ok(op_i64_trunc_sat_f64_s(rt_under))
  assert_stack_elem_eq(rt_under.stack[0], Value::I64(0x8000000000000000UL))
  let rt_nan_u = make_runtime([Value::F64(0.0 / 0.0)], [], 0)
  assert_ok(op_i64_trunc_sat_f64_u(rt_nan_u))
  assert_stack_elem_eq(rt_nan_u.stack[0], Value::I64(0UL))
  let rt_over_u = make_runtime([Value::F64(18446744073709551616.0)], [], 0)
  assert_ok(op_i64_trunc_sat_f64_u(rt_over_u))
  assert_stack_elem_eq(rt_over_u.stack[0], Value::I64(0xFFFFFFFFFFFFFFFFUL))
  let rt_under_u = make_runtime([Value::F64(-1.0)], [], 0)
  assert_ok(op_i64_trunc_sat_f64_u(rt_under_u))
  assert_stack_elem_eq(rt_under_u.stack[0], Value::I64(0UL))
}

///|
test "ops memory load/store and size" {
  let ops = [ImmediateIdx(0), ImmediateIdx(0)]
  let rt = make_runtime([], ops, 16)
  push_value(rt.stack, Value::I32(0U))
  push_value(rt.stack, Value::I32(0x11223344U))
  assert_ok(op_i32_store(rt))
  rt.stack.clear()
  rt.pc = 0
  push_value(rt.stack, Value::I32(0U))
  assert_ok(op_i32_load(rt))
  assert_stack_elem_eq(rt.stack[0], Value::I32(0x11223344U))
  rt.memory[0] = 0xFFU.to_byte()
  rt.stack.clear()
  rt.pc = 0
  push_value(rt.stack, Value::I32(0U))
  assert_ok(op_i32_load8_s(rt))
  assert_stack_elem_eq(rt.stack[0], Value::I32(0xFFFFFFFFU))
  rt.stack.clear()
  rt.pc = 0
  push_value(rt.stack, Value::I32(0U))
  assert_ok(op_i32_load8_u(rt))
  assert_stack_elem_eq(rt.stack[0], Value::I32(255U))
  rt.memory[0] = 0x00U.to_byte()
  rt.memory[1] = 0x80U.to_byte()
  rt.stack.clear()
  rt.pc = 0
  push_value(rt.stack, Value::I32(0U))
  assert_ok(op_i32_load16_s(rt))
  assert_stack_elem_eq(rt.stack[0], Value::I32(0xFFFF8000U))
  rt.stack.clear()
  rt.pc = 0
  push_value(rt.stack, Value::I32(0U))
  assert_ok(op_i32_load16_u(rt))
  assert_stack_elem_eq(rt.stack[0], Value::I32(0x8000U))
  let rt_size = make_runtime([], [], 65536)
  assert_ok(op_memory_size(rt_size))
  assert_stack_elem_eq(rt_size.stack[0], Value::I32(1U))
  let rt_grow = Runtime::{
    module_: empty_module(),
    ops: [],
    stack: [1UL], // i32(1) as UInt64
    sp: 0,
    num_locals: 0,
    locals: [],
    pc: 0,
    running: false,
    call_stack: [],
    memory: Array::make(65536, b'\x00'),
    memory_max: Some(2U),
    globals: [],
    tables: [],
    imported_funcs: [],
    data_segments: [],
    error_detail: "",
  }
  assert_ok(op_memory_grow(rt_grow))
  assert_stack_elem_eq(rt_grow.stack[0], Value::I32(1U))
}

///|
test "ops memory out of bounds and bulk ops" {
  let rt_oob = make_runtime([], [ImmediateIdx(0), ImmediateIdx(8)], 8)
  push_value(rt_oob.stack, Value::I32(0U))
  assert_ret(op_i32_load(rt_oob), MemoryOutOfBounds)
  let rt_oob_store = make_runtime([], [ImmediateIdx(0), ImmediateIdx(8)], 8)
  push_value(rt_oob_store.stack, Value::I32(0U))
  push_value(rt_oob_store.stack, Value::I32(1U))
  assert_ret(op_i32_store(rt_oob_store), MemoryOutOfBounds)
  let rt_i64 = make_runtime([], [ImmediateIdx(0), ImmediateIdx(0)], 16)
  push_value(rt_i64.stack, Value::I32(0U))
  push_value(rt_i64.stack, Value::I64(0x1122334455667788UL))
  assert_ok(op_i64_store(rt_i64))
  rt_i64.stack.clear()
  rt_i64.pc = 0
  push_value(rt_i64.stack, Value::I32(0U))
  assert_ok(op_i64_load(rt_i64))
  assert_stack_elem_eq(rt_i64.stack[0], Value::I64(0x1122334455667788UL))
  let rt_copy = make_runtime([], [], 8)
  rt_copy.memory[0] = 1U.to_byte()
  rt_copy.memory[1] = 2U.to_byte()
  rt_copy.memory[2] = 3U.to_byte()
  push_value(rt_copy.stack, Value::I32(0U))
  push_value(rt_copy.stack, Value::I32(0U))
  push_value(rt_copy.stack, Value::I32(3U))
  assert_ok(op_memory_copy(rt_copy))
  assert_eq(rt_copy.memory[0], 1U.to_byte())
  assert_eq(rt_copy.memory[1], 2U.to_byte())
  let rt_fill = make_runtime([], [], 8)
  push_value(rt_fill.stack, Value::I32(0U))
  push_value(rt_fill.stack, Value::I32(0x7FU))
  push_value(rt_fill.stack, Value::I32(3U))
  assert_ok(op_memory_fill(rt_fill))
  assert_eq(rt_fill.memory[0], 0x7FU.to_byte())
  assert_eq(rt_fill.memory[2], 0x7FU.to_byte())
  let rt_init = Runtime::{
    module_: empty_module(),
    ops: [ImmediateIdx(0), ImmediateIdx(0)],
    stack: [0UL, 0UL, 2UL], // i32 values as UInt64
    sp: 0,
    num_locals: 0,
    locals: [],
    pc: 0,
    running: false,
    call_stack: [],
    memory: Array::make(4, b'\x00'),
    memory_max: None,
    globals: [],
    tables: [],
    imported_funcs: [],
    data_segments: [[1U.to_byte(), 2U.to_byte(), 3U.to_byte()]],
    error_detail: "",
  }
  assert_ok(op_memory_init(rt_init))
  assert_eq(rt_init.memory[0], 1U.to_byte())
  assert_eq(rt_init.memory[1], 2U.to_byte())
  let rt_drop = Runtime::{
    module_: empty_module(),
    ops: [ImmediateIdx(0), ImmediateIdx(0)],
    stack: [],
    sp: 0,
    num_locals: 0,
    locals: [],
    pc: 0,
    running: false,
    call_stack: [],
    memory: Array::make(1, b'\x00'),
    memory_max: None,
    globals: [],
    tables: [],
    imported_funcs: [],
    data_segments: [[1U.to_byte()]],
    error_detail: "",
  }
  assert_ok(op_data_drop(rt_drop))
  assert_eq(rt_drop.data_segments[0].length(), 0)
}

///|
test "compile helpers canonicalize and counts" {
  let nan_f32 : Float = 0.0 / 0.0
  let nan_f64 : Double = 0.0 / 0.0
  assert_eq(f32_bits(canonicalize_f32(nan_f32)), f32_bits(canonical_nan_f32))
  assert_eq(f64_bits(canonicalize_f64(nan_f64)), f64_bits(canonical_nan_f64))
  let module_ : @core.Module = {
    types: [],
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    elems: [],
    datas: [],
    start: None,
    imports: [
      { module_: b"m", name: b"f", desc: Func(0U) },
      {
        module_: b"m",
        name: b"mem",
        desc: Mem({ limits: { min: 1U, max: None } }),
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
    funcs: [0U, 1U],
    tables: [],
    mems: [],
    globals: [],
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
  let args = rt.pop_arguments(func_type)
  assert_eq(args[0], Value::I32(2U))
  assert_eq(args[1], Value::I32(3U))
  assert_eq(rt.stack.length(), 1)
}

///|
test "compile context stack ops and errors" {
  let ctx = CompileCtx::new()
  ctx.push_type(I32)
  ctx.pop_type()
  ctx.push_types([I32, I64])
  ctx.pop_types(2)
  let cases : Array[(RetCode, RuntimeError)] = [
    (DivisionByZero, RuntimeError::DivisionByZero),
    (IntegerOverflow, RuntimeError::IntegerOverflow),
    (MemoryOutOfBounds, RuntimeError::MemoryOutOfBounds),
    (Unreachable, RuntimeError::Unreachable),
    (InvalidType, RuntimeError::InvalidType("x")),
    (FunctionNotCompiled, RuntimeError::FunctionNotCompiled("x")),
    (UnsupportedLocalType, RuntimeError::UnsupportedLocalType("x")),
  ]
  for case in cases {
    let (ret, expected) = case
    match (ret.to_error("x"), expected) {
      (RuntimeError::DivisionByZero, RuntimeError::DivisionByZero)
      | (RuntimeError::IntegerOverflow, RuntimeError::IntegerOverflow)
      | (RuntimeError::MemoryOutOfBounds, RuntimeError::MemoryOutOfBounds)
      | (RuntimeError::Unreachable, RuntimeError::Unreachable)
      | (RuntimeError::InvalidType(_), RuntimeError::InvalidType(_))
      | (
        RuntimeError::FunctionNotCompiled(_),
        RuntimeError::FunctionNotCompiled(_),
      )
      | (
        RuntimeError::UnsupportedLocalType(_),
        RuntimeError::UnsupportedLocalType(_),
      ) => ()
      _ => abort("unexpected error")
    }
  }
}

///|
test "panic pop helpers wrong types" {
  let rt_i64 = make_runtime([Value::I32(1U)], [], 0)
  ignore(rt_i64.pop_i64())
}

///|
test "panic pop helpers wrong pair types" {
  let rt = make_runtime([Value::I32(1U), Value::I64(2UL)], [], 0)
  ignore(rt.pop_two_i64())
}

///|
test "panic retcode ok to_error" {
  ignore(RetCode::OK.to_error("x"))
}

///|
test "panic pop helpers wrong float types" {
  let rt_f32 = make_runtime([Value::I32(1U)], [], 0)
  ignore(rt_f32.pop_f32())
}

///|
test "panic pop helpers wrong f64 type" {
  let rt_f64 = make_runtime([Value::I32(1U)], [], 0)
  ignore(rt_f64.pop_f64())
}
