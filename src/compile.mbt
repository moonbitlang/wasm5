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

// Memory operations
fn op_i32_load(rt : Runtime) -> ControlFlow {
  let offset = rt.read_imm_idx()
  let addr = rt.pop_i32().reinterpret_as_int() + offset
  if addr + 4 > rt.memory.length() {
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
  if addr + 4 > rt.memory.length() {
    return Trap(RuntimeError::MemoryOutOfBounds)
  }
  rt.memory[addr] = (value & 0xFFU).to_byte()
  rt.memory[addr + 1] = ((value >> 8) & 0xFFU).to_byte()
  rt.memory[addr + 2] = ((value >> 16) & 0xFFU).to_byte()
  rt.memory[addr + 3] = ((value >> 24) & 0xFFU).to_byte()
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

fn op_f64_neg(rt : Runtime) -> ControlFlow {
  let a = rt.pop_f64()
  rt.stack.push(Value::F64(-a))
  Next
}

// Float binary operations
fn op_f64_add(rt : Runtime) -> ControlFlow {
  let (a, b) = rt.pop_two_f64()
  rt.stack.push(Value::F64(a + b))
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
    F64Neg => self.emit(WasmInstr(op_f64_neg))
    // Float binary
    F64Add => self.emit(WasmInstr(op_f64_add))
    // Float conversions
    F64ConvertI64U => self.emit(WasmInstr(op_f64_convert_i64_u))
    F64ConvertI64S => self.emit(WasmInstr(op_f64_convert_i64_s))
    F64ConvertI32U => self.emit(WasmInstr(op_f64_convert_i32_u))
    F64ConvertI32S => self.emit(WasmInstr(op_f64_convert_i32_s))
    F64PromoteF32 => self.emit(WasmInstr(op_f64_promote_f32))
    // Truncations
    I64TruncF64S => self.emit(WasmInstr(op_i64_trunc_f64_s))
    I64TruncF64U => self.emit(WasmInstr(op_i64_trunc_f64_u))
    I32TruncF32S => self.emit(WasmInstr(op_i32_trunc_f32_s))
    I32TruncF32U => self.emit(WasmInstr(op_i32_trunc_f32_u))
    I32TruncF64S => self.emit(WasmInstr(op_i32_trunc_f64_s))
    I32TruncF64U => self.emit(WasmInstr(op_i32_trunc_f64_u))
    I64TruncF32S => self.emit(WasmInstr(op_i64_trunc_f32_s))
    I64TruncF32U => self.emit(WasmInstr(op_i64_trunc_f32_u))
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
    // Global instructions
    GlobalGet(idx) => {
      self.emit(WasmInstr(op_global_get))
      self.emit(ImmediateIdx(idx.reinterpret_as_int()))
    }
    GlobalSet(idx) => {
      self.emit(WasmInstr(op_global_set))
      self.emit(ImmediateIdx(idx.reinterpret_as_int()))
    }
    // Unsupported instructions - emit trap
    CallIndirect(_, _) => self.emit(WasmInstr(op_unsupported))
    MemoryGrow(_) => self.emit(WasmInstr(op_unsupported))
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
