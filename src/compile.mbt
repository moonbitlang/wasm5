// =============================================================================
// NaN Canonicalization for WebAssembly Compliance
// =============================================================================
//
// WebAssembly requires that when a floating-point operation produces a NaN
// result, it must be a "canonical NaN" with a specific bit pattern:
//
//   - f64 canonical NaN: 0x7FF8000000000000 (positive quiet NaN)
//   - f32 canonical NaN: 0x7FC00000 (positive quiet NaN)
//
// The sign bit must be 0 (positive), and the payload must be the canonical
// quiet NaN pattern.
//
// WHY THIS MATTERS:
// Native floating-point hardware may produce different NaN bit patterns when
// propagating NaN through operations. For example:
//   - Adding -0.0 + (-NaN) might produce a negative NaN (sign bit = 1)
//   - Different CPUs may set different payload bits
//
// The WebAssembly spec tests (wast files) check for exact bit patterns in
// "nan:canonical" assertions, so we must canonicalize all NaN results.
//
// WHICH OPERATIONS NEED CANONICALIZATION:
// Any operation that can produce NaN as a result needs canonicalization:
//   - Arithmetic: add, sub, mul, div (when operands include NaN or produce NaN)
//   - Unary: sqrt (negative input), ceil, floor, trunc, nearest (NaN passthrough)
//   - Min/max: when either operand is NaN
//
// Note: Operations like neg, abs, and copysign have special NaN handling
// defined by the spec and don't use canonicalization.
// =============================================================================

///|
/// Canonical NaN values for WebAssembly
/// f64 canonical NaN: 0x7FF8000000000000
let canonical_nan_f64 : Double = 0x7ff8_0000_0000_0000UL.reinterpret_as_double()

/// f32 canonical NaN: 0x7FC00000
let canonical_nan_f32 : Float = Float::reinterpret_from_uint(0x7fc0_0000U)

///|
/// Canonicalize NaN values - if value is NaN, return canonical NaN.
/// This ensures WebAssembly spec compliance for NaN bit patterns.
fn canonicalize_f64(v : Double) -> Double {
  if v.is_nan() { canonical_nan_f64 } else { v }
}

///|
/// Canonicalize NaN values - if value is NaN, return canonical NaN.
/// This ensures WebAssembly spec compliance for NaN bit patterns.
fn canonicalize_f32(v : Float) -> Float {
  if v.is_nan() { canonical_nan_f32 } else { v }
}

///|
/// Intermediate instruction for threaded interpreter
enum MInstr {
  WasmInstr((Runtime) -> ControlFlow)
  ImmediateI32(UInt)
  ImmediateIdx(Int)
}

///|
/// Control flow signal from instruction execution
enum ControlFlow {
  Next // Continue to next instruction
  Jump(Int) // Jump to specific PC
  End // Stop execution
  Trap(RuntimeError) // Trap with error
}

///|
/// Call frame for function calls
struct CallFrame {
  return_pc : Int
  locals : Array[Value]
}

///|
/// Emit an instruction to the ops array
fn Runtime::emit(self : Runtime, instr : MInstr) -> Unit {
  self.ops.push(instr)
}

///|
/// Read immediate i32 value and advance PC
fn Runtime::read_imm_i32(self : Runtime) -> UInt {
  self.pc += 1
  guard self.ops.unsafe_get(self.pc) is ImmediateI32(value)
  value
}

///|
/// Read immediate index value and advance PC
fn Runtime::read_imm_idx(self : Runtime) -> Int {
  self.pc += 1
  guard self.ops.unsafe_get(self.pc) is ImmediateIdx(value)
  value
}

// ============================================================================
// Helper to pop two i32 values
// ============================================================================

fn Runtime::pop_two_i32(self : Runtime) -> (UInt, UInt) {
  let b = self.stack.unsafe_pop()
  let a = self.stack.unsafe_pop()
  match (a, b) {
    (Value::I32(a_val), Value::I32(b_val)) => (a_val, b_val)
    _ => abort("Type error: expected two i32 values")
  }
}

fn Runtime::pop_i32(self : Runtime) -> UInt {
  match self.stack.unsafe_pop() {
    Value::I32(v) => v
    _ => abort("Type error: expected i32")
  }
}

// ============================================================================
// i32 instruction implementations
// ============================================================================

fn op_i32_const(rt : Runtime) -> ControlFlow {
  let value = rt.read_imm_i32()
  rt.stack.push(Value::I32(value))
  Next
}

fn op_i32_add(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(a + b))
  Next
}

fn op_i32_sub(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(a - b))
  Next
}

fn op_i32_mul(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(a * b))
  Next
}

fn op_i32_div_s(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  if b == 0U {
    return Trap(RuntimeError::DivisionByZero)
  }
  if a == 0x80000000U && b == 0xFFFFFFFFU {
    return Trap(RuntimeError::IntegerOverflow)
  }
  let result = (a.reinterpret_as_int() / b.reinterpret_as_int()).reinterpret_as_uint()
  rt.stack.push(Value::I32(result))
  Next
}

fn op_i32_div_u(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  if b == 0U {
    return Trap(RuntimeError::DivisionByZero)
  }
  rt.stack.push(Value::I32(a / b))
  Next
}

fn op_i32_rem_s(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  if b == 0U {
    return Trap(RuntimeError::DivisionByZero)
  }
  let result = (a.reinterpret_as_int() % b.reinterpret_as_int()).reinterpret_as_uint()
  rt.stack.push(Value::I32(result))
  Next
}

fn op_i32_rem_u(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  if b == 0U {
    return Trap(RuntimeError::DivisionByZero)
  }
  rt.stack.push(Value::I32(a % b))
  Next
}

fn op_i32_and(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(a & b))
  Next
}

fn op_i32_or(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(a | b))
  Next
}

fn op_i32_xor(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(a ^ b))
  Next
}

fn op_i32_shl(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  let shift = (b & 0x1FU).reinterpret_as_int()
  rt.stack.push(Value::I32(a << shift))
  Next
}

fn op_i32_shr_s(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  let shift = (b & 0x1FU).reinterpret_as_int()
  let result = (a.reinterpret_as_int() >> shift).reinterpret_as_uint()
  rt.stack.push(Value::I32(result))
  Next
}

fn op_i32_shr_u(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  let shift = (b & 0x1FU).reinterpret_as_int()
  rt.stack.push(Value::I32(a >> shift))
  Next
}

fn op_i32_rotl(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  let rotation = (b & 0x1FU).reinterpret_as_int()
  let result = (a << rotation) | (a >> (32 - rotation))
  rt.stack.push(Value::I32(result))
  Next
}

fn op_i32_rotr(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  let rotation = (b & 0x1FU).reinterpret_as_int()
  let result = (a >> rotation) | (a << (32 - rotation))
  rt.stack.push(Value::I32(result))
  Next
}

// Comparison operations
fn op_i32_eq(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(if a == b { 1U } else { 0U }))
  Next
}

fn op_i32_ne(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(if a != b { 1U } else { 0U }))
  Next
}

fn op_i32_lt_s(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  let result = if a.reinterpret_as_int() < b.reinterpret_as_int() { 1U } else { 0U }
  rt.stack.push(Value::I32(result))
  Next
}

fn op_i32_lt_u(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(if a < b { 1U } else { 0U }))
  Next
}

fn op_i32_gt_s(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  let result = if a.reinterpret_as_int() > b.reinterpret_as_int() { 1U } else { 0U }
  rt.stack.push(Value::I32(result))
  Next
}

fn op_i32_gt_u(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(if a > b { 1U } else { 0U }))
  Next
}

fn op_i32_le_s(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  let result = if a.reinterpret_as_int() <= b.reinterpret_as_int() { 1U } else { 0U }
  rt.stack.push(Value::I32(result))
  Next
}

fn op_i32_le_u(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(if a <= b { 1U } else { 0U }))
  Next
}

fn op_i32_ge_s(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  let result = if a.reinterpret_as_int() >= b.reinterpret_as_int() { 1U } else { 0U }
  rt.stack.push(Value::I32(result))
  Next
}

fn op_i32_ge_u(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i32()
  rt.stack.push(Value::I32(if a >= b { 1U } else { 0U }))
  Next
}

// Unary operations
fn op_i32_eqz(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i32()
  rt.stack.push(Value::I32(if a == 0U { 1U } else { 0U }))
  Next
}

fn op_i32_clz(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i32()
  rt.stack.push(Value::I32(a.clz().reinterpret_as_uint()))
  Next
}

fn op_i32_ctz(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i32()
  rt.stack.push(Value::I32(a.ctz().reinterpret_as_uint()))
  Next
}

fn op_i32_popcnt(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i32()
  rt.stack.push(Value::I32(a.popcnt().reinterpret_as_uint()))
  Next
}

fn op_i32_extend8_s(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i32()
  let byte = a & 0xFFU
  let result = if (byte & 0x80U) != 0U { byte | 0xFFFFFF00U } else { byte }
  rt.stack.push(Value::I32(result))
  Next
}

fn op_i32_extend16_s(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i32()
  let half = a & 0xFFFFU
  let result = if (half & 0x8000U) != 0U { half | 0xFFFF0000U } else { half }
  rt.stack.push(Value::I32(result))
  Next
}

fn op_i32_wrap_i64(rt : Runtime) -> ControlFlow {
  match rt.stack.unsafe_pop() {
    Value::I64(v) => rt.stack.push(Value::I32((v & 0xFFFFFFFFUL).to_uint()))
    _ => abort("Type error: expected i64")
  }
  Next
}

// ============================================================================
// i64 instruction implementations
// ============================================================================

fn Runtime::pop_two_i64(self : Runtime) -> (UInt64, UInt64) {
  let b = self.stack.unsafe_pop()
  let a = self.stack.unsafe_pop()
  match (a, b) {
    (Value::I64(a_val), Value::I64(b_val)) => (a_val, b_val)
    _ => abort("Type error: expected two i64 values")
  }
}

fn Runtime::pop_i64(self : Runtime) -> UInt64 {
  match self.stack.unsafe_pop() {
    Value::I64(v) => v
    _ => abort("Type error: expected i64")
  }
}

fn op_i64_const(rt : Runtime) -> ControlFlow {
  // Read two i32 immediates to form i64
  let low = rt.read_imm_i32()
  let high = rt.read_imm_i32()
  let value = low.to_uint64() | (high.to_uint64() << 32)
  rt.stack.push(Value::I64(value))
  Next
}

fn op_f32_const(rt : Runtime) -> ControlFlow {
  let bits = rt.read_imm_i32()
  rt.stack.push(Value::F32(Float::reinterpret_from_uint(bits)))
  Next
}

fn op_f64_const(rt : Runtime) -> ControlFlow {
  let low = rt.read_imm_i32()
  let high = rt.read_imm_i32()
  let bits = low.to_uint64() | (high.to_uint64() << 32)
  rt.stack.push(Value::F64(bits.reinterpret_as_double()))
  Next
}

fn op_i64_add(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I64(a + b))
  Next
}

fn op_i64_sub(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I64(a - b))
  Next
}

fn op_i64_mul(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I64(a * b))
  Next
}

fn op_i64_div_s(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  if b == 0UL {
    return Trap(RuntimeError::DivisionByZero)
  }
  if a == 0x8000000000000000UL && b == 0xFFFFFFFFFFFFFFFFUL {
    return Trap(RuntimeError::IntegerOverflow)
  }
  let result = (a.reinterpret_as_int64() / b.reinterpret_as_int64()).reinterpret_as_uint64()
  rt.stack.push(Value::I64(result))
  Next
}

fn op_i64_div_u(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  if b == 0UL {
    return Trap(RuntimeError::DivisionByZero)
  }
  rt.stack.push(Value::I64(a / b))
  Next
}

fn op_i64_rem_s(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  if b == 0UL {
    return Trap(RuntimeError::DivisionByZero)
  }
  let result = (a.reinterpret_as_int64() % b.reinterpret_as_int64()).reinterpret_as_uint64()
  rt.stack.push(Value::I64(result))
  Next
}

fn op_i64_rem_u(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  if b == 0UL {
    return Trap(RuntimeError::DivisionByZero)
  }
  rt.stack.push(Value::I64(a % b))
  Next
}

fn op_i64_and(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I64(a & b))
  Next
}

fn op_i64_or(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I64(a | b))
  Next
}

fn op_i64_xor(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I64(a ^ b))
  Next
}

fn op_i64_shl(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  let shift = (b & 0x3FUL).to_int()
  rt.stack.push(Value::I64(a << shift))
  Next
}

fn op_i64_shr_s(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  let shift = (b & 0x3FUL).to_int()
  let result = (a.reinterpret_as_int64() >> shift).reinterpret_as_uint64()
  rt.stack.push(Value::I64(result))
  Next
}

fn op_i64_shr_u(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  let shift = (b & 0x3FUL).to_int()
  rt.stack.push(Value::I64(a >> shift))
  Next
}

fn op_i64_rotl(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  let rotation = (b & 0x3FUL).to_int()
  let result = (a << rotation) | (a >> (64 - rotation))
  rt.stack.push(Value::I64(result))
  Next
}

fn op_i64_rotr(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  let rotation = (b & 0x3FUL).to_int()
  let result = (a >> rotation) | (a << (64 - rotation))
  rt.stack.push(Value::I64(result))
  Next
}

// i64 comparison operations
fn op_i64_eq(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I32(if a == b { 1U } else { 0U }))
  Next
}

fn op_i64_ne(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I32(if a != b { 1U } else { 0U }))
  Next
}

fn op_i64_lt_s(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  let result = if a.reinterpret_as_int64() < b.reinterpret_as_int64() { 1U } else { 0U }
  rt.stack.push(Value::I32(result))
  Next
}

fn op_i64_lt_u(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I32(if a < b { 1U } else { 0U }))
  Next
}

fn op_i64_gt_s(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  let result = if a.reinterpret_as_int64() > b.reinterpret_as_int64() { 1U } else { 0U }
  rt.stack.push(Value::I32(result))
  Next
}

fn op_i64_gt_u(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I32(if a > b { 1U } else { 0U }))
  Next
}

fn op_i64_le_s(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  let result = if a.reinterpret_as_int64() <= b.reinterpret_as_int64() { 1U } else { 0U }
  rt.stack.push(Value::I32(result))
  Next
}

fn op_i64_le_u(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I32(if a <= b { 1U } else { 0U }))
  Next
}

fn op_i64_ge_s(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  let result = if a.reinterpret_as_int64() >= b.reinterpret_as_int64() { 1U } else { 0U }
  rt.stack.push(Value::I32(result))
  Next
}

fn op_i64_ge_u(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_i64()
  rt.stack.push(Value::I32(if a >= b { 1U } else { 0U }))
  Next
}

// i64 unary operations
fn op_i64_eqz(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i64()
  rt.stack.push(Value::I32(if a == 0UL { 1U } else { 0U }))
  Next
}

fn op_i64_clz(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i64()
  rt.stack.push(Value::I64(a.clz().to_uint64()))
  Next
}

fn op_i64_ctz(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i64()
  rt.stack.push(Value::I64(a.ctz().to_uint64()))
  Next
}

fn op_i64_popcnt(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i64()
  rt.stack.push(Value::I64(a.popcnt().to_uint64()))
  Next
}

fn op_i64_extend8_s(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i64()
  let byte = a & 0xFFUL
  let result = if (byte & 0x80UL) != 0UL { byte | 0xFFFFFFFFFFFFFF00UL } else { byte }
  rt.stack.push(Value::I64(result))
  Next
}

fn op_i64_extend16_s(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i64()
  let half = a & 0xFFFFUL
  let result = if (half & 0x8000UL) != 0UL { half | 0xFFFFFFFFFFFF0000UL } else { half }
  rt.stack.push(Value::I64(result))
  Next
}

fn op_i64_extend32_s(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i64()
  let word = a & 0xFFFFFFFFUL
  let result = if (word & 0x80000000UL) != 0UL { word | 0xFFFFFFFF00000000UL } else { word }
  rt.stack.push(Value::I64(result))
  Next
}

fn op_i64_extend_i32_s(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i32()
  let result = a.reinterpret_as_int().to_int64().reinterpret_as_uint64()
  rt.stack.push(Value::I64(result))
  Next
}

fn op_i64_extend_i32_u(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i32()
  rt.stack.push(Value::I64(a.to_uint64()))
  Next
}

// ============================================================================
// Local/Global variable operations
// ============================================================================

fn op_local_get(rt : Runtime) -> ControlFlow {
  let idx = rt.read_imm_idx()
  rt.stack.push(rt.locals[idx])
  Next
}

fn op_local_set(rt : Runtime) -> ControlFlow {
  let idx = rt.read_imm_idx()
  let value = rt.stack.unsafe_pop()
  rt.locals[idx] = value
  Next
}

fn op_local_tee(rt : Runtime) -> ControlFlow {
  let idx = rt.read_imm_idx()
  let value = rt.stack[rt.stack.length() - 1]
  rt.locals[idx] = value
  Next
}

// ============================================================================
// Stack operations
// ============================================================================

fn op_drop(rt : Runtime) -> ControlFlow {
  let _ = rt.stack.unsafe_pop()
  Next
}

fn op_select(rt : Runtime) -> ControlFlow {
  let cond = rt.pop_i32()
  let val2 = rt.stack.unsafe_pop()
  let val1 = rt.stack.unsafe_pop()
  rt.stack.push(if cond != 0U { val1 } else { val2 })
  Next
}

// ============================================================================
// Control flow operations
// ============================================================================

fn op_if(rt : Runtime) -> ControlFlow {
  let else_pc = rt.read_imm_idx()
  let cond = rt.pop_i32()
  if cond != 0U { Next } else { Jump(else_pc) }
}

fn op_else(rt : Runtime) -> ControlFlow {
  let end_pc = rt.read_imm_idx()
  Jump(end_pc)
}

fn op_end_block(rt : Runtime) -> ControlFlow {
  let _ = rt.branch_targets.unsafe_pop()
  Next
}

fn op_push_block_target(rt : Runtime) -> ControlFlow {
  let target_pc = rt.read_imm_idx()
  rt.branch_targets.push(target_pc)
  Next
}

fn op_push_loop_target(rt : Runtime) -> ControlFlow {
  let target_pc = rt.read_imm_idx()
  rt.branch_targets.push(target_pc)
  Next
}

fn op_br(rt : Runtime) -> ControlFlow {
  let label = rt.read_imm_idx()
  let target_idx = rt.branch_targets.length() - 1 - label
  if target_idx < 0 || target_idx >= rt.branch_targets.length() {
    return Trap(
      RuntimeError::InvalidType(
        "br: invalid branch target index \{target_idx} (label=\{label}, targets=\{rt.branch_targets.length()})",
      ),
    )
  }
  let target_pc = rt.branch_targets[target_idx]
  // Pop all targets up to and including the target
  for _i = 0; _i <= label; _i = _i + 1 {
    let _ = rt.branch_targets.unsafe_pop()
  }
  Jump(target_pc)
}

fn op_br_if(rt : Runtime) -> ControlFlow {
  let label = rt.read_imm_idx()
  let cond = rt.pop_i32()
  if cond != 0U {
    let target_idx = rt.branch_targets.length() - 1 - label
    if target_idx < 0 || target_idx >= rt.branch_targets.length() {
      return Trap(
        RuntimeError::InvalidType(
          "br_if: invalid branch target index \{target_idx} (label=\{label}, targets=\{rt.branch_targets.length()})",
        ),
      )
    }
    let target_pc = rt.branch_targets[target_idx]
    // Pop all targets up to and including the target
    for _i = 0; _i <= label; _i = _i + 1 {
      let _ = rt.branch_targets.unsafe_pop()
    }
    Jump(target_pc)
  } else {
    Next
  }
}

fn op_br_table(rt : Runtime) -> ControlFlow {
  let num_labels = rt.read_imm_idx()
  let index = rt.pop_i32().reinterpret_as_int()
  // Read all labels and default
  let mut target_label = 0
  for i = 0; i <= num_labels; i = i + 1 {
    let label = rt.read_imm_idx()
    if i == index && i < num_labels {
      target_label = label
    } else if i == num_labels && (index < 0 || index >= num_labels) {
      // Default label
      target_label = label
    }
  }
  let target_idx = rt.branch_targets.length() - 1 - target_label
  if target_idx < 0 || target_idx >= rt.branch_targets.length() {
    return Trap(
      RuntimeError::InvalidType(
        "br_table: invalid branch target index \{target_idx}",
      ),
    )
  }
  let target_pc = rt.branch_targets[target_idx]
  // Pop all targets up to and including the target
  for _i = 0; _i <= target_label; _i = _i + 1 {
    let _ = rt.branch_targets.unsafe_pop()
  }
  Jump(target_pc)
}

fn op_call(rt : Runtime) -> ControlFlow {
  let func_idx = rt.read_imm_idx()
  let type_idx = rt.module_.funcs[func_idx].reinterpret_as_int()
  let func_type = rt.module_.types[type_idx]
  let code = rt.module_.codes[func_idx]

  guard code.compiled is Some(callee_pc) else {
    return Trap(RuntimeError::FunctionNotCompiled("Function not compiled: \{func_idx}"))
  }

  // Pop arguments
  let num_params = func_type.params.length()
  let args : Array[Value] = Array::make(num_params, Value::I32(0U))
  for i = num_params - 1; i >= 0; i = i - 1 {
    args[i] = rt.stack.unsafe_pop()
  }

  // Save frame
  rt.call_stack.push(CallFrame::{ return_pc: rt.pc, locals: rt.locals })

  // Set up new locals
  rt.locals = []
  for arg in args {
    rt.locals.push(arg)
  }
  for local_type in code.locals {
    match local_type {
      ValType::I32 => rt.locals.push(Value::I32(0U))
      ValType::I64 => rt.locals.push(Value::I64(0UL))
      ValType::F32 => rt.locals.push(Value::F32(0.0))
      ValType::F64 => rt.locals.push(Value::F64(0.0))
      _ =>
        return Trap(
          RuntimeError::UnsupportedLocalType("Unsupported local type: \{local_type}"),
        )
    }
  }

  Jump(callee_pc)
}

fn op_return(rt : Runtime) -> ControlFlow {
  if rt.call_stack.length() == 0 {
    return End
  }
  let return_value : Value? = if rt.stack.length() > 0 {
    Some(rt.stack.unsafe_pop())
  } else {
    None
  }
  let frame = rt.call_stack.unsafe_pop()
  rt.locals = frame.locals
  match return_value {
    Some(v) => rt.stack.push(v)
    None => ()
  }
  Jump(frame.return_pc + 1)
}

fn op_unsupported(_rt : Runtime) -> ControlFlow {
  Trap(RuntimeError::UnimplementedInstruction("unsupported instruction"))
}

fn op_end(rt : Runtime) -> ControlFlow {
  if rt.call_stack.length() > 0 { op_return(rt) } else { End }
}

fn op_nop(_rt : Runtime) -> ControlFlow {
  Next
}

fn op_unreachable(_rt : Runtime) -> ControlFlow {
  Trap(RuntimeError::Unreachable)
}

// =============================================================================
// Memory Operations - Bounds Checking
// =============================================================================
//
// IMPORTANT: Memory address bounds checking must check for BOTH:
//   1. addr < 0 (negative addresses)
//   2. addr + size > memory.length() (overflow past end)
//
// WHY NEGATIVE ADDRESS CHECK IS NEEDED:
// WebAssembly addresses are unsigned 32-bit values, but when we convert them
// to signed integers for array indexing (via reinterpret_as_int()), large
// unsigned values (>= 2^31) become negative signed values.
//
// For example:
//   - Address 0xFFFFFFFF (u32 max) becomes -1 when reinterpreted as signed
//   - Without the addr < 0 check, this would cause an array index out of bounds
//     crash instead of a proper WebAssembly trap
//
// The check `addr < 0` catches these cases and returns MemoryOutOfBounds trap.
// =============================================================================

fn op_i32_load(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 4 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  let b0 = rt.memory[addr].to_uint()
  let b1 = rt.memory[addr + 1].to_uint()
  let b2 = rt.memory[addr + 2].to_uint()
  let b3 = rt.memory[addr + 3].to_uint()
  rt.stack.push(Value::I32(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)))
  Next
}

fn op_i32_store(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let value = rt.pop_i32()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 4 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  rt.memory[addr] = (value & 0xFFU).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFU).to_byte()
  rt.memory[addr + 2] = ((value >> 16) & 0xFFU).to_byte()
  rt.memory[addr + 3] = ((value >> 24) & 0xFFU).to_byte()
  Next
}

// Additional memory load operations
fn op_i32_load8_s(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 1 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  let b = rt.memory[addr].to_int()
  // Sign extend from 8 bits
  let value = if b >= 128 { b - 256 } else { b }
  rt.stack.push(Value::I32(value.reinterpret_as_uint()))
  Next
}

fn op_i32_load8_u(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 1 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  rt.stack.push(Value::I32(rt.memory[addr].to_uint()))
  Next
}

fn op_i32_load16_s(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 2 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  let b0 = rt.memory[addr].to_int()
  let b1 = rt.memory[addr + 1].to_int()
  let value16 = b0 | (b1 << 8)
  // Sign extend from 16 bits
  let value = if value16 >= 32768 { value16 - 65536 } else { value16 }
  rt.stack.push(Value::I32(value.reinterpret_as_uint()))
  Next
}

fn op_i32_load16_u(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 2 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  let b0 = rt.memory[addr].to_uint()
  let b1 = rt.memory[addr + 1].to_uint()
  rt.stack.push(Value::I32(b0 | (b1 << 8)))
  Next
}

fn op_i64_load(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 8 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  let b0 = rt.memory[addr].to_uint64()
  let b1 = rt.memory[addr + 1].to_uint64()
  let b2 = rt.memory[addr + 2].to_uint64()
  let b3 = rt.memory[addr + 3].to_uint64()
  let b4 = rt.memory[addr + 4].to_uint64()
  let b5 = rt.memory[addr + 5].to_uint64()
  let b6 = rt.memory[addr + 6].to_uint64()
  let b7 = rt.memory[addr + 7].to_uint64()
  rt.stack.push(Value::I64(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24) | (b4 << 32) | (b5 << 40) | (b6 << 48) | (b7 << 56)))
  Next
}

fn op_i64_store(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let value = rt.pop_i64()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 8 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  rt.memory[addr] = (value & 0xFFUL).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
  rt.memory[addr + 2] = ((value >> 16) & 0xFFUL).to_byte()
  rt.memory[addr + 3] = ((value >> 24) & 0xFFUL).to_byte()
  rt.memory[addr + 4] = ((value >> 32) & 0xFFUL).to_byte()
  rt.memory[addr + 5] = ((value >> 40) & 0xFFUL).to_byte()
  rt.memory[addr + 6] = ((value >> 48) & 0xFFUL).to_byte()
  rt.memory[addr + 7] = ((value >> 56) & 0xFFUL).to_byte()
  Next
}

fn op_i64_load8_s(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 1 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  let b = rt.memory[addr].to_int64()
  // Sign extend from 8 bits
  let value = if b >= 128L { b - 256L } else { b }
  rt.stack.push(Value::I64(value.reinterpret_as_uint64()))
  Next
}

fn op_i64_load8_u(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 1 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  rt.stack.push(Value::I64(rt.memory[addr].to_uint64()))
  Next
}

fn op_i64_load16_s(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 2 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  let b0 = rt.memory[addr].to_int64()
  let b1 = rt.memory[addr + 1].to_int64()
  let value16 = b0 | (b1 << 8)
  // Sign extend from 16 bits
  let value = if value16 >= 32768L { value16 - 65536L } else { value16 }
  rt.stack.push(Value::I64(value.reinterpret_as_uint64()))
  Next
}

fn op_i64_load16_u(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 2 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  let b0 = rt.memory[addr].to_uint64()
  let b1 = rt.memory[addr + 1].to_uint64()
  rt.stack.push(Value::I64(b0 | (b1 << 8)))
  Next
}

fn op_i64_load32_s(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 4 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  let b0 = rt.memory[addr].to_int64()
  let b1 = rt.memory[addr + 1].to_int64()
  let b2 = rt.memory[addr + 2].to_int64()
  let b3 = rt.memory[addr + 3].to_int64()
  let value32 = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
  // Sign extend from 32 bits
  let value = if value32 >= 0x80000000L { value32 - 0x100000000L } else { value32 }
  rt.stack.push(Value::I64(value.reinterpret_as_uint64()))
  Next
}

fn op_i64_load32_u(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 4 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  let b0 = rt.memory[addr].to_uint64()
  let b1 = rt.memory[addr + 1].to_uint64()
  let b2 = rt.memory[addr + 2].to_uint64()
  let b3 = rt.memory[addr + 3].to_uint64()
  rt.stack.push(Value::I64(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)))
  Next
}

fn op_f32_load(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 4 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  let b0 = rt.memory[addr].to_uint()
  let b1 = rt.memory[addr + 1].to_uint()
  let b2 = rt.memory[addr + 2].to_uint()
  let b3 = rt.memory[addr + 3].to_uint()
  let bits = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
  rt.stack.push(Value::F32(Float::reinterpret_from_uint(bits)))
  Next
}

fn op_f64_load(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 8 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  let b0 = rt.memory[addr].to_uint64()
  let b1 = rt.memory[addr + 1].to_uint64()
  let b2 = rt.memory[addr + 2].to_uint64()
  let b3 = rt.memory[addr + 3].to_uint64()
  let b4 = rt.memory[addr + 4].to_uint64()
  let b5 = rt.memory[addr + 5].to_uint64()
  let b6 = rt.memory[addr + 6].to_uint64()
  let b7 = rt.memory[addr + 7].to_uint64()
  let bits = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24) | (b4 << 32) | (b5 << 40) | (b6 << 48) | (b7 << 56)
  rt.stack.push(Value::F64(bits.reinterpret_as_double()))
  Next
}

fn op_f32_store(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let value = rt.pop_f32().reinterpret_as_uint()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 4 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  rt.memory[addr] = (value & 0xFFU).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFU).to_byte()
  rt.memory[addr + 2] = ((value >> 16) & 0xFFU).to_byte()
  rt.memory[addr + 3] = ((value >> 24) & 0xFFU).to_byte()
  Next
}

fn op_f64_store(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let value = rt.pop_f64().reinterpret_as_uint64()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 8 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  rt.memory[addr] = (value & 0xFFUL).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
  rt.memory[addr + 2] = ((value >> 16) & 0xFFUL).to_byte()
  rt.memory[addr + 3] = ((value >> 24) & 0xFFUL).to_byte()
  rt.memory[addr + 4] = ((value >> 32) & 0xFFUL).to_byte()
  rt.memory[addr + 5] = ((value >> 40) & 0xFFUL).to_byte()
  rt.memory[addr + 6] = ((value >> 48) & 0xFFUL).to_byte()
  rt.memory[addr + 7] = ((value >> 56) & 0xFFUL).to_byte()
  Next
}

// Narrow store operations
fn op_i32_store8(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let value = rt.pop_i32()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 1 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  rt.memory[addr] = (value & 0xFFU).to_byte()
  Next
}

fn op_i32_store16(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let value = rt.pop_i32()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 2 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  rt.memory[addr] = (value & 0xFFU).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFU).to_byte()
  Next
}

fn op_i64_store8(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let value = rt.pop_i64()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 1 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  rt.memory[addr] = (value & 0xFFUL).to_byte()
  Next
}

fn op_i64_store16(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let value = rt.pop_i64()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 2 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  rt.memory[addr] = (value & 0xFFUL).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
  Next
}

fn op_i64_store32(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let value = rt.pop_i64()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr < 0 || addr + 4 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  rt.memory[addr] = (value & 0xFFUL).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFUL).to_byte()
  rt.memory[addr + 2] = ((value >> 16) & 0xFFUL).to_byte()
  rt.memory[addr + 3] = ((value >> 24) & 0xFFUL).to_byte()
  Next
}

// Memory size and grow operations
// WebAssembly memory is measured in pages of 64KB (65536 bytes)
let wasm_page_size : Int = 65536

fn op_memory_size(rt : Runtime) -> ControlFlow {
  // Return current memory size in pages
  let size_in_pages = rt.memory.length() / wasm_page_size
  rt.stack.push(Value::I32(size_in_pages.reinterpret_as_uint()))
  Next
}

fn op_memory_grow(rt : Runtime) -> ControlFlow {
  let delta_pages = rt.pop_i32().reinterpret_as_int()
  let old_size_pages = rt.memory.length() / wasm_page_size

  // Check for overflow or negative delta
  if delta_pages < 0 {
    rt.stack.push(Value::I32(0xFFFFFFFFU)) // -1 indicates failure
    return Next
  }

  let new_size_pages = old_size_pages + delta_pages

  // Check against maximum memory limit (if defined in module)
  // For now, use a reasonable default max of 256 pages (16MB)
  // TODO: Read actual max from module's memory type
  let max_pages = 256
  if new_size_pages > max_pages {
    rt.stack.push(Value::I32(0xFFFFFFFFU)) // -1 indicates failure
    return Next
  }

  // Grow the memory by appending zero bytes
  let bytes_to_add = delta_pages * wasm_page_size
  for i = 0; i < bytes_to_add; i = i + 1 {
    rt.memory.push(b'\x00')
  }

  // Return old size in pages (success)
  rt.stack.push(Value::I32(old_size_pages.reinterpret_as_uint()))
  Next
}

// =============================================================================
// Table operations
// =============================================================================

fn op_table_size(rt : Runtime) -> ControlFlow {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    return Trap(RuntimeError::InvalidType("table index out of bounds"))
  }
  let size = rt.tables[table_idx].data.length()
  rt.stack.push(Value::I32(size.reinterpret_as_uint()))
  Next
}

fn op_table_get(rt : Runtime) -> ControlFlow {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    return Trap(RuntimeError::InvalidType("table index out of bounds"))
  }
  let elem_idx = rt.pop_i32().reinterpret_as_int()
  let table = rt.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    return Trap(RuntimeError::InvalidType("table element index out of bounds"))
  }
  // Return the function reference (or null)
  rt.stack.push(Value::Ref(table[elem_idx]))
  Next
}

fn op_table_set(rt : Runtime) -> ControlFlow {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    return Trap(RuntimeError::InvalidType("table index out of bounds"))
  }
  let ref_value = match rt.stack.unsafe_pop() {
    Value::Ref(r) => r
    _ => return Trap(RuntimeError::InvalidType("expected funcref for table.set"))
  }
  let elem_idx = rt.pop_i32().reinterpret_as_int()
  let table = rt.tables[table_idx].data
  if elem_idx < 0 || elem_idx >= table.length() {
    return Trap(RuntimeError::InvalidType("table element index out of bounds"))
  }
  table[elem_idx] = ref_value
  Next
}

fn op_table_grow(rt : Runtime) -> ControlFlow {
  let table_idx = rt.read_imm_idx()
  if table_idx < 0 || table_idx >= rt.tables.length() {
    rt.stack.push(Value::I32(0xFFFFFFFFU)) // -1 indicates failure
    return Next
  }
  let delta = rt.pop_i32().reinterpret_as_int()
  let init_value = match rt.stack.unsafe_pop() {
    Value::Ref(r) => r
    _ => {
      rt.stack.push(Value::I32(0xFFFFFFFFU))
      return Next
    }
  }
  let runtime_table = rt.tables[table_idx]
  let table = runtime_table.data
  let old_size = table.length()

  if delta < 0 {
    rt.stack.push(Value::I32(0xFFFFFFFFU)) // -1 indicates failure
    return Next
  }

  let new_size = old_size + delta

  // Check max limit
  match runtime_table.max {
    Some(max) =>
      if new_size > max.reinterpret_as_int() {
        // Would exceed max - return -1 (failure)
        rt.stack.push(Value::I32(0xFFFFFFFFU))
        return Next
      }
    None => () // No max limit
  }

  // Grow the table
  for i = 0; i < delta; i = i + 1 {
    table.push(init_value)
  }

  rt.stack.push(Value::I32(old_size.reinterpret_as_uint()))
  Next
}

// =============================================================================
// Reference operations
// =============================================================================

fn op_ref_null(rt : Runtime) -> ControlFlow {
  // ref.null pushes a null reference onto the stack
  // The heap type is encoded in the immediate but we don't need it at runtime
  let _ = rt.read_imm_idx() // Skip the heap type encoding
  rt.stack.push(Value::Ref(None))
  Next
}

fn op_ref_func(rt : Runtime) -> ControlFlow {
  // ref.func pushes a reference to the given function onto the stack
  let func_idx = rt.read_imm_idx()
  rt.stack.push(Value::Ref(Some(func_idx)))
  Next
}

fn op_ref_is_null(rt : Runtime) -> ControlFlow {
  // ref.is_null tests whether a reference is null
  let ref_val = rt.stack.unsafe_pop()
  let is_null = match ref_val {
    Value::Ref(None) => 1U
    Value::Ref(Some(_)) => 0U
    _ => 0U // Non-ref values are considered not null
  }
  rt.stack.push(Value::I32(is_null))
  Next
}

// Float operations
fn Runtime::pop_f32(self : Runtime) -> Float {
  match self.stack.unsafe_pop() {
    Value::F32(v) => v
    _ => abort("Type error: expected f32")
  }
}

fn Runtime::pop_two_f32(self : Runtime) -> (Float, Float) {
  let b = self.pop_f32()
  let a = self.pop_f32()
  (a, b)
}

fn Runtime::pop_f64(self : Runtime) -> Double {
  match self.stack.unsafe_pop() {
    Value::F64(v) => v
    _ => abort("Type error: expected f64")
  }
}

fn Runtime::pop_two_f64(self : Runtime) -> (Double, Double) {
  let b = self.pop_f64()
  let a = self.pop_f64()
  (a, b)
}

fn op_f32_eq(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::I32(if a == b { 1U } else { 0U }))
  Next
}

fn op_f32_ne(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::I32(if a != b { 1U } else { 0U }))
  Next
}

fn op_f32_lt(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::I32(if a < b { 1U } else { 0U }))
  Next
}

fn op_f32_gt(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::I32(if a > b { 1U } else { 0U }))
  Next
}

fn op_f32_le(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::I32(if a <= b { 1U } else { 0U }))
  Next
}

fn op_f32_ge(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::I32(if a >= b { 1U } else { 0U }))
  Next
}

fn op_f64_eq(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::I32(if a == b { 1U } else { 0U }))
  Next
}

fn op_f64_ne(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::I32(if a != b { 1U } else { 0U }))
  Next
}

fn op_f64_lt(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::I32(if a < b { 1U } else { 0U }))
  Next
}

fn op_f64_gt(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::I32(if a > b { 1U } else { 0U }))
  Next
}

fn op_f64_le(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::I32(if a <= b { 1U } else { 0U }))
  Next
}

fn op_f64_ge(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::I32(if a >= b { 1U } else { 0U }))
  Next
}

// Float unary operations
fn op_f32_neg(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(-a))
  Next
}

fn op_f32_abs(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(a.abs()))
  Next
}

fn op_f32_sqrt(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a.sqrt())))
  Next
}

fn op_f32_ceil(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a.ceil())))
  Next
}

fn op_f32_floor(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a.floor())))
  Next
}

fn op_f32_trunc(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a.trunc())))
  Next
}

fn op_f32_nearest(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a.round())))
  Next
}

fn op_f64_neg(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(-a))
  Next
}

// Float binary operations
fn op_f32_add(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a + b)))
  Next
}

fn op_f32_sub(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a - b)))
  Next
}

fn op_f32_mul(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a * b)))
  Next
}

fn op_f32_div(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f32()
  rt.stack.push(Value::F32(canonicalize_f32(a / b)))
  Next
}

fn op_f32_min(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f32()
  let result = if a.is_nan() || b.is_nan() {
    canonical_nan_f32
  } else if a < b {
    a
  } else {
    b
  }
  rt.stack.push(Value::F32(result))
  Next
}

fn op_f32_max(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f32()
  let result = if a.is_nan() || b.is_nan() {
    canonical_nan_f32
  } else if a > b {
    a
  } else {
    b
  }
  rt.stack.push(Value::F32(result))
  Next
}

fn op_f32_copysign(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f32()
  let a_bits = a.reinterpret_as_uint()
  let b_bits = b.reinterpret_as_uint()
  let sign_mask = 0x8000_0000U
  let result_bits = (a_bits & sign_mask.lnot()) | (b_bits & sign_mask)
  rt.stack.push(Value::F32(Float::reinterpret_from_uint(result_bits)))
  Next
}

fn op_f64_add(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a + b)))
  Next
}

fn op_f64_sub(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a - b)))
  Next
}

fn op_f64_mul(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a * b)))
  Next
}

fn op_f64_div(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a / b)))
  Next
}

fn op_f64_min(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f64()
  // WebAssembly min semantics: if either is NaN, return canonical NaN
  let result = if a.is_nan() || b.is_nan() {
    canonical_nan_f64
  } else if a < b {
    a
  } else {
    b
  }
  rt.stack.push(Value::F64(result))
  Next
}

fn op_f64_max(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f64()
  // WebAssembly max semantics: if either is NaN, return canonical NaN
  let result = if a.is_nan() || b.is_nan() {
    canonical_nan_f64
  } else if a > b {
    a
  } else {
    b
  }
  rt.stack.push(Value::F64(result))
  Next
}

fn op_f64_copysign(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f64()
  let a_bits = a.reinterpret_as_uint64()
  let b_bits = b.reinterpret_as_uint64()
  let sign_mask = 0x8000_0000_0000_0000UL
  let result_bits = (a_bits & sign_mask.lnot()) | (b_bits & sign_mask)
  rt.stack.push(Value::F64(result_bits.reinterpret_as_double()))
  Next
}

// Float unary operations
fn op_f64_abs(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(a.abs()))
  Next
}

fn op_f64_sqrt(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a.sqrt())))
  Next
}

fn op_f64_ceil(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a.ceil())))
  Next
}

fn op_f64_floor(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a.floor())))
  Next
}

fn op_f64_trunc(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a.trunc())))
  Next
}

fn op_f64_nearest(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(canonicalize_f64(a.round())))
  Next
}

// Float conversion operations
fn op_f64_convert_i64_u(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i64()
  rt.stack.push(Value::F64(a.to_double()))
  Next
}

fn op_f64_convert_i64_s(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i64().reinterpret_as_int64()
  rt.stack.push(Value::F64(a.to_double()))
  Next
}

fn op_f64_convert_i32_u(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i32()
  rt.stack.push(Value::F64(a.to_double()))
  Next
}

fn op_f64_convert_i32_s(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i32().reinterpret_as_int()
  rt.stack.push(Value::F64(a.to_double()))
  Next
}

fn op_f64_promote_f32(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f32()
  rt.stack.push(Value::F64(a.to_double()))
  Next
}

fn op_f32_demote_f64(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f64()
  rt.stack.push(Value::F32(a.to_float()))
  Next
}

fn op_f32_convert_i32_s(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i32().reinterpret_as_int()
  rt.stack.push(Value::F32(a.to_float()))
  Next
}

fn op_f32_convert_i32_u(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i32()
  rt.stack.push(Value::F32(a.to_double().to_float()))
  Next
}

fn op_f32_convert_i64_s(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i64().reinterpret_as_int64()
  rt.stack.push(Value::F32(a.to_double().to_float()))
  Next
}

fn op_f32_convert_i64_u(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i64()
  // For unsigned i64 to float, handle large values carefully
  let f = if a.reinterpret_as_int64() >= 0L {
    a.reinterpret_as_int64().to_double()
  } else {
    // For values >= 2^63, convert via double
    (a >> 1).reinterpret_as_int64().to_double() * 2.0 + (a & 1UL).to_double()
  }
  rt.stack.push(Value::F32(f.to_float()))
  Next
}

// Truncation operations
fn op_i64_trunc_f64_s(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f64()
  rt.stack.push(Value::I64(a.to_int64().reinterpret_as_uint64()))
  Next
}

fn op_i64_trunc_f64_u(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f64()
  rt.stack.push(Value::I64(a.to_uint64()))
  Next
}

fn op_i32_trunc_f32_s(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f32()
  rt.stack.push(Value::I32(a.to_int().reinterpret_as_uint()))
  Next
}

fn op_i32_trunc_f32_u(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f32()
  rt.stack.push(Value::I32(a.to_int().reinterpret_as_uint()))
  Next
}

fn op_i32_trunc_f64_s(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f64()
  rt.stack.push(Value::I32(a.to_int().reinterpret_as_uint()))
  Next
}

fn op_i32_trunc_f64_u(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f64()
  rt.stack.push(Value::I32(a.to_int().reinterpret_as_uint()))
  Next
}

fn op_i64_trunc_f32_s(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f32()
  rt.stack.push(Value::I64(a.to_double().to_int64().reinterpret_as_uint64()))
  Next
}

fn op_i64_trunc_f32_u(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f32()
  rt.stack.push(Value::I64(a.to_double().to_uint64()))
  Next
}

// Reinterpret operations
fn op_i32_reinterpret_f32(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f32()
  rt.stack.push(Value::I32(a.reinterpret_as_uint()))
  Next
}

fn op_i64_reinterpret_f64(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f64()
  rt.stack.push(Value::I64(a.reinterpret_as_uint64()))
  Next
}

fn op_f32_reinterpret_i32(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i32()
  rt.stack.push(Value::F32(Float::reinterpret_from_uint(a)))
  Next
}

fn op_f64_reinterpret_i64(rt : Runtime) -> ControlFlow {
  let a = rt.pop_i64()
  rt.stack.push(Value::F64(a.reinterpret_as_double()))
  Next
}

// Global operations
fn op_global_get(rt : Runtime) -> ControlFlow {
  let idx = rt.read_imm_idx()
  rt.stack.push(rt.globals[idx])
  Next
}

fn op_global_set(rt : Runtime) -> ControlFlow {
  let idx = rt.read_imm_idx()
  let value = rt.stack.unsafe_pop()
  rt.globals[idx] = value
  Next
}

// ============================================================================
// Compilation
// ============================================================================

fn Runtime::compile_wasm_instr(
  self : Runtime,
  instr : Instr,
) -> Unit raise RuntimeError {
  match instr {
    // Constants
    I32Const(value) => {
      self.emit(WasmInstr(op_i32_const))
      self.emit(ImmediateI32(value))
    }
    // Arithmetic
    I32Add => self.emit(WasmInstr(op_i32_add))
    I32Sub => self.emit(WasmInstr(op_i32_sub))
    I32Mul => self.emit(WasmInstr(op_i32_mul))
    I32DivS => self.emit(WasmInstr(op_i32_div_s))
    I32DivU => self.emit(WasmInstr(op_i32_div_u))
    I32RemS => self.emit(WasmInstr(op_i32_rem_s))
    I32RemU => self.emit(WasmInstr(op_i32_rem_u))
    // Bitwise
    I32And => self.emit(WasmInstr(op_i32_and))
    I32Or => self.emit(WasmInstr(op_i32_or))
    I32Xor => self.emit(WasmInstr(op_i32_xor))
    I32Shl => self.emit(WasmInstr(op_i32_shl))
    I32ShrS => self.emit(WasmInstr(op_i32_shr_s))
    I32ShrU => self.emit(WasmInstr(op_i32_shr_u))
    I32Rotl => self.emit(WasmInstr(op_i32_rotl))
    I32Rotr => self.emit(WasmInstr(op_i32_rotr))
    // Comparison
    I32Eq => self.emit(WasmInstr(op_i32_eq))
    I32Ne => self.emit(WasmInstr(op_i32_ne))
    I32LtS => self.emit(WasmInstr(op_i32_lt_s))
    I32LtU => self.emit(WasmInstr(op_i32_lt_u))
    I32GtS => self.emit(WasmInstr(op_i32_gt_s))
    I32GtU => self.emit(WasmInstr(op_i32_gt_u))
    I32LeS => self.emit(WasmInstr(op_i32_le_s))
    I32LeU => self.emit(WasmInstr(op_i32_le_u))
    I32GeS => self.emit(WasmInstr(op_i32_ge_s))
    I32GeU => self.emit(WasmInstr(op_i32_ge_u))
    // Unary
    I32Eqz => self.emit(WasmInstr(op_i32_eqz))
    I32Clz => self.emit(WasmInstr(op_i32_clz))
    I32Ctz => self.emit(WasmInstr(op_i32_ctz))
    I32Popcnt => self.emit(WasmInstr(op_i32_popcnt))
    I32Extend8S => self.emit(WasmInstr(op_i32_extend8_s))
    I32Extend16S => self.emit(WasmInstr(op_i32_extend16_s))
    I32WrapI64 => self.emit(WasmInstr(op_i32_wrap_i64))
    // i64 Constants
    I64Const(value) => {
      self.emit(WasmInstr(op_i64_const))
      // Split i64 into two i32 immediates
      self.emit(ImmediateI32((value & 0xFFFFFFFFUL).to_uint()))
      self.emit(ImmediateI32((value >> 32).to_uint()))
    }
    // f32/f64 Constants
    F32Const(value) => {
      self.emit(WasmInstr(op_f32_const))
      self.emit(ImmediateI32(value.reinterpret_as_uint()))
    }
    F64Const(value) => {
      self.emit(WasmInstr(op_f64_const))
      let bits = value.reinterpret_as_uint64()
      self.emit(ImmediateI32((bits & 0xFFFFFFFFUL).to_uint()))
      self.emit(ImmediateI32((bits >> 32).to_uint()))
    }
    // i64 Arithmetic
    I64Add => self.emit(WasmInstr(op_i64_add))
    I64Sub => self.emit(WasmInstr(op_i64_sub))
    I64Mul => self.emit(WasmInstr(op_i64_mul))
    I64DivS => self.emit(WasmInstr(op_i64_div_s))
    I64DivU => self.emit(WasmInstr(op_i64_div_u))
    I64RemS => self.emit(WasmInstr(op_i64_rem_s))
    I64RemU => self.emit(WasmInstr(op_i64_rem_u))
    // i64 Bitwise
    I64And => self.emit(WasmInstr(op_i64_and))
    I64Or => self.emit(WasmInstr(op_i64_or))
    I64Xor => self.emit(WasmInstr(op_i64_xor))
    I64Shl => self.emit(WasmInstr(op_i64_shl))
    I64ShrS => self.emit(WasmInstr(op_i64_shr_s))
    I64ShrU => self.emit(WasmInstr(op_i64_shr_u))
    I64Rotl => self.emit(WasmInstr(op_i64_rotl))
    I64Rotr => self.emit(WasmInstr(op_i64_rotr))
    // i64 Comparison
    I64Eq => self.emit(WasmInstr(op_i64_eq))
    I64Ne => self.emit(WasmInstr(op_i64_ne))
    I64LtS => self.emit(WasmInstr(op_i64_lt_s))
    I64LtU => self.emit(WasmInstr(op_i64_lt_u))
    I64GtS => self.emit(WasmInstr(op_i64_gt_s))
    I64GtU => self.emit(WasmInstr(op_i64_gt_u))
    I64LeS => self.emit(WasmInstr(op_i64_le_s))
    I64LeU => self.emit(WasmInstr(op_i64_le_u))
    I64GeS => self.emit(WasmInstr(op_i64_ge_s))
    I64GeU => self.emit(WasmInstr(op_i64_ge_u))
    // i64 Unary
    I64Eqz => self.emit(WasmInstr(op_i64_eqz))
    I64Clz => self.emit(WasmInstr(op_i64_clz))
    I64Ctz => self.emit(WasmInstr(op_i64_ctz))
    I64Popcnt => self.emit(WasmInstr(op_i64_popcnt))
    I64Extend8S => self.emit(WasmInstr(op_i64_extend8_s))
    I64Extend16S => self.emit(WasmInstr(op_i64_extend16_s))
    I64Extend32S => self.emit(WasmInstr(op_i64_extend32_s))
    I64ExtendI32S => self.emit(WasmInstr(op_i64_extend_i32_s))
    I64ExtendI32U => self.emit(WasmInstr(op_i64_extend_i32_u))
    // Float comparisons
    F32Eq => self.emit(WasmInstr(op_f32_eq))
    F32Ne => self.emit(WasmInstr(op_f32_ne))
    F32Lt => self.emit(WasmInstr(op_f32_lt))
    F32Gt => self.emit(WasmInstr(op_f32_gt))
    F32Le => self.emit(WasmInstr(op_f32_le))
    F32Ge => self.emit(WasmInstr(op_f32_ge))
    F64Eq => self.emit(WasmInstr(op_f64_eq))
    F64Ne => self.emit(WasmInstr(op_f64_ne))
    F64Lt => self.emit(WasmInstr(op_f64_lt))
    F64Gt => self.emit(WasmInstr(op_f64_gt))
    F64Le => self.emit(WasmInstr(op_f64_le))
    F64Ge => self.emit(WasmInstr(op_f64_ge))
    // Float unary
    F32Neg => self.emit(WasmInstr(op_f32_neg))
    F32Abs => self.emit(WasmInstr(op_f32_abs))
    F32Sqrt => self.emit(WasmInstr(op_f32_sqrt))
    F32Ceil => self.emit(WasmInstr(op_f32_ceil))
    F32Floor => self.emit(WasmInstr(op_f32_floor))
    F32Trunc => self.emit(WasmInstr(op_f32_trunc))
    F32Nearest => self.emit(WasmInstr(op_f32_nearest))
    F64Neg => self.emit(WasmInstr(op_f64_neg))
    F64Abs => self.emit(WasmInstr(op_f64_abs))
    F64Sqrt => self.emit(WasmInstr(op_f64_sqrt))
    F64Ceil => self.emit(WasmInstr(op_f64_ceil))
    F64Floor => self.emit(WasmInstr(op_f64_floor))
    F64Trunc => self.emit(WasmInstr(op_f64_trunc))
    F64Nearest => self.emit(WasmInstr(op_f64_nearest))
    // Float binary
    F32Add => self.emit(WasmInstr(op_f32_add))
    F32Sub => self.emit(WasmInstr(op_f32_sub))
    F32Mul => self.emit(WasmInstr(op_f32_mul))
    F32Div => self.emit(WasmInstr(op_f32_div))
    F32Min => self.emit(WasmInstr(op_f32_min))
    F32Max => self.emit(WasmInstr(op_f32_max))
    F32Copysign => self.emit(WasmInstr(op_f32_copysign))
    F64Add => self.emit(WasmInstr(op_f64_add))
    F64Sub => self.emit(WasmInstr(op_f64_sub))
    F64Mul => self.emit(WasmInstr(op_f64_mul))
    F64Div => self.emit(WasmInstr(op_f64_div))
    F64Min => self.emit(WasmInstr(op_f64_min))
    F64Max => self.emit(WasmInstr(op_f64_max))
    F64Copysign => self.emit(WasmInstr(op_f64_copysign))
    // Float conversions
    F64ConvertI64U => self.emit(WasmInstr(op_f64_convert_i64_u))
    F64ConvertI64S => self.emit(WasmInstr(op_f64_convert_i64_s))
    F64ConvertI32U => self.emit(WasmInstr(op_f64_convert_i32_u))
    F64ConvertI32S => self.emit(WasmInstr(op_f64_convert_i32_s))
    F64PromoteF32 => self.emit(WasmInstr(op_f64_promote_f32))
    F32DemoteF64 => self.emit(WasmInstr(op_f32_demote_f64))
    F32ConvertI32S => self.emit(WasmInstr(op_f32_convert_i32_s))
    F32ConvertI32U => self.emit(WasmInstr(op_f32_convert_i32_u))
    F32ConvertI64S => self.emit(WasmInstr(op_f32_convert_i64_s))
    F32ConvertI64U => self.emit(WasmInstr(op_f32_convert_i64_u))
    // Truncations
    I64TruncF64S => self.emit(WasmInstr(op_i64_trunc_f64_s))
    I64TruncF64U => self.emit(WasmInstr(op_i64_trunc_f64_u))
    I32TruncF32S => self.emit(WasmInstr(op_i32_trunc_f32_s))
    I32TruncF32U => self.emit(WasmInstr(op_i32_trunc_f32_u))
    I32TruncF64S => self.emit(WasmInstr(op_i32_trunc_f64_s))
    I32TruncF64U => self.emit(WasmInstr(op_i32_trunc_f64_u))
    I64TruncF32S => self.emit(WasmInstr(op_i64_trunc_f32_s))
    I64TruncF32U => self.emit(WasmInstr(op_i64_trunc_f32_u))
    // Reinterpret
    I32ReinterpretF32 => self.emit(WasmInstr(op_i32_reinterpret_f32))
    I64ReinterpretF64 => self.emit(WasmInstr(op_i64_reinterpret_f64))
    F32ReinterpretI32 => self.emit(WasmInstr(op_f32_reinterpret_i32))
    F64ReinterpretI64 => self.emit(WasmInstr(op_f64_reinterpret_i64))
    // Locals
    LocalGet(idx) => {
      self.emit(WasmInstr(op_local_get))
      self.emit(ImmediateIdx(idx.reinterpret_as_int()))
    }
    LocalSet(idx) => {
      self.emit(WasmInstr(op_local_set))
      self.emit(ImmediateIdx(idx.reinterpret_as_int()))
    }
    LocalTee(idx) => {
      self.emit(WasmInstr(op_local_tee))
      self.emit(ImmediateIdx(idx.reinterpret_as_int()))
    }
    // Stack
    Drop => self.emit(WasmInstr(op_drop))
    Select => self.emit(WasmInstr(op_select))
    Nop => self.emit(WasmInstr(op_nop))
    Unreachable => self.emit(WasmInstr(op_unreachable))
    // Control flow
    Block(_block_type, instrs) => {
      // Push block target (placeholder, will be patched)
      self.emit(WasmInstr(op_push_block_target))
      let target_slot = self.ops.length()
      self.emit(ImmediateIdx(0)) // Placeholder

      for instr in instrs {
        self.compile_wasm_instr(instr)
      }

      self.emit(WasmInstr(op_end_block))
      // Patch the target to point AFTER end_block (br skips past end_block)
      self.ops[target_slot] = ImmediateIdx(self.ops.length())
    }
    Loop(_block_type, instrs) => {
      // Push loop target (points to start of loop body)
      self.emit(WasmInstr(op_push_loop_target))
      let loop_body_start = self.ops.length() + 1 // After the immediate
      self.emit(ImmediateIdx(loop_body_start))

      for instr in instrs {
        self.compile_wasm_instr(instr)
      }

      self.emit(WasmInstr(op_end_block))
    }
    Br(label) => {
      self.emit(WasmInstr(op_br))
      self.emit(ImmediateIdx(label.reinterpret_as_int()))
    }
    BrIf(label) => {
      self.emit(WasmInstr(op_br_if))
      self.emit(ImmediateIdx(label.reinterpret_as_int()))
    }
    BrTable(labels, default_label) => {
      self.emit(WasmInstr(op_br_table))
      self.emit(ImmediateIdx(labels.length()))
      for label in labels {
        self.emit(ImmediateIdx(label.reinterpret_as_int()))
      }
      self.emit(ImmediateIdx(default_label.reinterpret_as_int()))
    }
    If(_block_type, then_instrs, else_instrs) => {
      // Push branch target for the If block (br 0 inside will jump to end)
      self.emit(WasmInstr(op_push_block_target))
      let end_target_slot = self.ops.length()
      self.emit(ImmediateIdx(0)) // Placeholder for end_pc

      self.emit(WasmInstr(op_if))
      let else_pc_slot = self.ops.length()
      self.emit(ImmediateIdx(0))

      for instr in then_instrs {
        self.compile_wasm_instr(instr)
      }

      self.emit(WasmInstr(op_else))
      let end_pc_slot = self.ops.length()
      self.emit(ImmediateIdx(0))

      let else_start = self.ops.length()
      self.ops[else_pc_slot] = ImmediateIdx(else_start)

      for instr in else_instrs {
        self.compile_wasm_instr(instr)
      }

      self.emit(WasmInstr(op_end_block))
      let end_pc = self.ops.length() - 1
      self.ops[end_pc_slot] = ImmediateIdx(end_pc)
      // Branch target points AFTER end_block (br skips past end_block)
      self.ops[end_target_slot] = ImmediateIdx(self.ops.length())
    }
    Call(func_idx) => {
      self.emit(WasmInstr(op_call))
      self.emit(ImmediateIdx(func_idx.reinterpret_as_int()))
    }
    Return => self.emit(WasmInstr(op_return))
    // Memory instructions
    I32Load(_align, offset) => {
      self.emit(WasmInstr(op_i32_load))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I32Store(_align, offset) => {
      self.emit(WasmInstr(op_i32_store))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I32Load8S(_align, offset) => {
      self.emit(WasmInstr(op_i32_load8_s))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I32Load8U(_align, offset) => {
      self.emit(WasmInstr(op_i32_load8_u))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I32Load16S(_align, offset) => {
      self.emit(WasmInstr(op_i32_load16_s))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I32Load16U(_align, offset) => {
      self.emit(WasmInstr(op_i32_load16_u))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I32Store8(_align, offset) => {
      self.emit(WasmInstr(op_i32_store8))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I32Store16(_align, offset) => {
      self.emit(WasmInstr(op_i32_store16))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Load(_align, offset) => {
      self.emit(WasmInstr(op_i64_load))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Store(_align, offset) => {
      self.emit(WasmInstr(op_i64_store))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Load8S(_align, offset) => {
      self.emit(WasmInstr(op_i64_load8_s))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Load8U(_align, offset) => {
      self.emit(WasmInstr(op_i64_load8_u))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Load16S(_align, offset) => {
      self.emit(WasmInstr(op_i64_load16_s))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Load16U(_align, offset) => {
      self.emit(WasmInstr(op_i64_load16_u))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Load32S(_align, offset) => {
      self.emit(WasmInstr(op_i64_load32_s))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Load32U(_align, offset) => {
      self.emit(WasmInstr(op_i64_load32_u))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Store8(_align, offset) => {
      self.emit(WasmInstr(op_i64_store8))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Store16(_align, offset) => {
      self.emit(WasmInstr(op_i64_store16))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    I64Store32(_align, offset) => {
      self.emit(WasmInstr(op_i64_store32))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    F32Load(_align, offset) => {
      self.emit(WasmInstr(op_f32_load))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    F32Store(_align, offset) => {
      self.emit(WasmInstr(op_f32_store))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    F64Load(_align, offset) => {
      self.emit(WasmInstr(op_f64_load))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    F64Store(_align, offset) => {
      self.emit(WasmInstr(op_f64_store))
      self.emit(ImmediateIdx(offset.reinterpret_as_int()))
    }
    // Global instructions
    GlobalGet(idx) => {
      self.emit(WasmInstr(op_global_get))
      self.emit(ImmediateIdx(idx.reinterpret_as_int()))
    }
    GlobalSet(idx) => {
      self.emit(WasmInstr(op_global_set))
      self.emit(ImmediateIdx(idx.reinterpret_as_int()))
    }
    // Memory size and grow
    MemorySize(_) => self.emit(WasmInstr(op_memory_size))
    MemoryGrow(_) => self.emit(WasmInstr(op_memory_grow))
    // Table instructions
    TableSize(table_idx) => {
      self.emit(WasmInstr(op_table_size))
      self.emit(ImmediateIdx(table_idx.reinterpret_as_int()))
    }
    TableGet(table_idx) => {
      self.emit(WasmInstr(op_table_get))
      self.emit(ImmediateIdx(table_idx.reinterpret_as_int()))
    }
    TableSet(table_idx) => {
      self.emit(WasmInstr(op_table_set))
      self.emit(ImmediateIdx(table_idx.reinterpret_as_int()))
    }
    TableGrow(table_idx) => {
      self.emit(WasmInstr(op_table_grow))
      self.emit(ImmediateIdx(table_idx.reinterpret_as_int()))
    }
    // Reference instructions
    RefNull(ref_type) => {
      self.emit(WasmInstr(op_ref_null))
      // Encode the ref type as an immediate (0 for funcref, 1 for externref)
      let type_idx = match ref_type {
        FuncRef => 0
        ExternRef => 1
      }
      self.emit(ImmediateIdx(type_idx))
    }
    RefFunc(func_idx) => {
      self.emit(WasmInstr(op_ref_func))
      self.emit(ImmediateIdx(func_idx.reinterpret_as_int()))
    }
    RefIsNull => self.emit(WasmInstr(op_ref_is_null))
    // Unsupported instructions - emit trap
    CallIndirect(_, _) => self.emit(WasmInstr(op_unsupported))
    _ =>
      raise RuntimeError::UnimplementedInstruction(
        "Unimplemented instruction: \{instr}",
      )
  }
}

fn Runtime::compile_func(
  self : Runtime,
  code : Code,
) -> Unit raise RuntimeError {
  let start_pc = self.ops.length()
  for instr in code.body.instrs {
    self.compile_wasm_instr(instr)
  }
  self.emit(WasmInstr(op_end))
  code.compiled = Some(start_pc)
}

pub fn Runtime::compile(self : Runtime) -> Unit raise RuntimeError {
  for code in self.module_.codes {
    self.compile_func(code)
  }
}

fn Runtime::execute(self : Runtime) -> Unit raise RuntimeError {
  while true {
    guard self.ops.unsafe_get(self.pc) is WasmInstr(f) else {
      raise RuntimeError::UnimplementedInstruction(
        "Expected instruction at PC \{self.pc}",
      )
    }
    match f(self) {
      Next => self.pc += 1
      Jump(target) => self.pc = target
      End => return
      Trap(err) => raise err
    }
  }
}

pub fn Runtime::call_compiled(
  self : Runtime,
  func_name : Bytes,
  args : Array[Value],
) -> Array[Value] raise RuntimeError {
  let func_name_str = func_name.to_string()
  let mut func_idx : Int? = None
  for exp in self.module_.exports {
    if exp.name == func_name_str {
      match exp.desc {
        Func(idx) => {
          func_idx = Some(idx.reinterpret_as_int())
          break
        }
        _ => continue
      }
    }
  }
  guard func_idx is Some(idx) else {
    raise RuntimeError::FunctionNotFound("Function not found: \{func_name}")
  }

  let type_idx = self.module_.funcs[idx].reinterpret_as_int()
  let func_type = self.module_.types[type_idx]
  let code = self.module_.codes[idx]

  guard code.compiled is Some(start_pc) else {
    raise RuntimeError::FunctionNotCompiled("Function not compiled: \{func_name}")
  }

  self.locals = []
  for arg in args {
    self.locals.push(arg)
  }
  for local_type in code.locals {
    match local_type {
      ValType::I32 => self.locals.push(Value::I32(0U))
      ValType::I64 => self.locals.push(Value::I64(0UL))
      ValType::F32 => self.locals.push(Value::F32(0.0))
      ValType::F64 => self.locals.push(Value::F64(0.0))
      _ =>
        raise RuntimeError::UnsupportedLocalType(
          "Unsupported local type: \{local_type}",
        )
    }
  }

  self.stack.clear()
  self.call_stack.clear()
  self.pc = start_pc
  self.execute()

  let results : Array[Value] = []
  for _i = 0; _i < func_type.results.length(); _i = _i + 1 {
    if self.stack.length() > 0 {
      results.push(self.stack.unsafe_pop())
    }
  }
  results.rev_in_place()
  results
}
